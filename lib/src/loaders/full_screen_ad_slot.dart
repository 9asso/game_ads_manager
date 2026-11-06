import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_paid_event.dart';
import '../ads_logger.dart';
import '../logic/clock.dart';
import '../logic/retry_backoff.dart';

/// Starts loading one ad. Must call [onLoaded] or [onFailed] later.
typedef AdLoadFunction<T extends AdWithoutView> =
    Future<void> Function({
      required String adUnitId,
      required void Function(T ad) onLoaded,
      required void Function(LoadAdError error) onFailed,
    });

/// Keeps ONE full-screen ad of type [T] loaded and fresh.
///
/// * Retries failed loads with exponential backoff.
/// * Discards and reloads an ad older than [maxAge] (ads expire after ~1h).
/// * [take] hands the ad over for showing; call [load] again once it was
///   dismissed or failed to show.
class FullScreenAdSlot<T extends AdWithoutView> {
  /// Creates a slot. Call [load] to start.
  FullScreenAdSlot({
    required this.format,
    required this.adUnitId,
    required AdLoadFunction<T> loader,
    required AdsLogger logger,
    ValueNotifier<bool>? readyNotifier,
    this.maxAge = const Duration(minutes: 55),
    RetryBackoff? backoff,
    Clock clock = systemClock,
  }) : _loader = loader,
       _log = logger,
       _ready = readyNotifier,
       _backoff = backoff ?? RetryBackoff(),
       _clock = clock;

  /// Format (for logs).
  final AdFormat format;

  /// Ad unit ID being loaded.
  final String adUnitId;

  /// Maximum age of a cached ad before it is discarded.
  final Duration maxAge;

  final AdLoadFunction<T> _loader;
  final AdsLogger _log;
  final ValueNotifier<bool>? _ready;
  final RetryBackoff _backoff;
  final Clock _clock;

  T? _ad;
  DateTime? _loadedAt;
  bool _loading = false;
  bool _disposed = false;
  Timer? _retryTimer;
  Timer? _expiryTimer;

  /// Whether a fresh ad is cached and ready to show.
  bool get isReady => _ad != null && !_isExpired;

  bool get _isExpired {
    final loadedAt = _loadedAt;
    return loadedAt == null || _clock().difference(loadedAt) >= maxAge;
  }

  /// Starts loading unless an ad is already cached or loading.
  void load() {
    if (_disposed || _loading || _ad != null) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _loading = true;
    _log.info('${format.name}: loading…');
    unawaited(_startLoad());
  }

  Future<void> _startLoad() async {
    try {
      await _loader(
        adUnitId: adUnitId,
        onLoaded: _handleLoaded,
        onFailed: (error) =>
            _handleFailure('code ${error.code}: ${error.message}'),
      );
    } catch (e) {
      _handleFailure('exception: $e');
    }
  }

  void _handleLoaded(T ad) {
    if (_disposed) {
      _disposeAd(ad);
      return;
    }
    _loading = false;
    _ad = ad;
    _loadedAt = _clock();
    _backoff.reset();
    _setReady(true);
    final source =
        ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName ?? 'unknown';
    _log.info('${format.name}: loaded (source: $source)');
    _expiryTimer?.cancel();
    _expiryTimer = Timer(maxAge, _discardExpired);
  }

  void _handleFailure(String reason) {
    if (_disposed) return;
    _loading = false;
    _setReady(false);
    final delay = _backoff.nextDelay();
    _log.error(
      '${format.name}: load failed ($reason) – retry #${_backoff.failures} '
      'in ${delay.inSeconds}s',
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, load);
  }

  void _discardExpired() {
    final ad = _ad;
    if (_disposed || ad == null) return;
    _log.info('${format.name}: cached ad expired, reloading');
    _clear();
    _disposeAd(ad);
    load();
  }

  /// Returns the cached ad and removes it from the slot, or `null` if none is
  /// ready (in that case a load is started if none is pending).
  ///
  /// The caller owns the returned ad: it must show and dispose it, then call
  /// [load] for the next one.
  T? take() {
    if (_disposed) return null;
    final ad = _ad;
    if (ad == null) {
      if (!_loading && _retryTimer == null) load();
      return null;
    }
    if (_isExpired) {
      // Timers may not fire while the app is in the background.
      _discardExpired();
      return null;
    }
    _clear();
    return ad;
  }

  void _clear() {
    _ad = null;
    _loadedAt = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _setReady(false);
  }

  void _setReady(bool value) {
    final notifier = _ready;
    if (notifier != null && notifier.value != value) notifier.value = value;
  }

  /// Stops loading and frees the cached ad.
  void dispose() {
    if (_disposed) return;
    final ad = _ad;
    _clear();
    _disposed = true;
    _retryTimer?.cancel();
    if (ad != null) _disposeAd(ad);
  }

  void _disposeAd(Ad ad) {
    unawaited(
      ad.dispose().catchError((Object e) {
        _log.error('${format.name}: dispose failed', e);
      }),
    );
  }
}
