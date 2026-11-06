import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_paid_event.dart';
import '../ads_manager.dart';
import '../logic/retry_backoff.dart';

/// Shared logic for inline ads (banner, native): waits until ads are
/// allowed, loads, retries with backoff, hides when "remove ads" is active,
/// and disposes correctly. Takes no space until an ad is loaded.
abstract class InlineAdState<W extends StatefulWidget, A extends AdWithView>
    extends State<W> {
  /// Format handled by this widget.
  AdFormat get format;

  /// Creates the ad (without loading it). Wire the callbacks into its
  /// listener. Return `null` to skip loading.
  Future<A?> createAd(
    String adUnitId, {
    required void Function(Ad ad) onLoaded,
    required void Function(Ad ad, LoadAdError error) onFailed,
    required OnPaidEventCallback onPaid,
  });

  /// Builds the widget for a loaded [ad].
  Widget buildLoaded(BuildContext context, A ad);

  /// The shared manager.
  AdsManager get manager => AdsManager.instance;

  A? _ad;
  bool _loaded = false;
  int _generation = 0;
  Timer? _retryTimer;
  final RetryBackoff _backoff = RetryBackoff();

  @override
  void initState() {
    super.initState();
    manager.inlineAdsAllowed.addListener(reload);
  }

  @override
  void dispose() {
    manager.inlineAdsAllowed.removeListener(reload);
    _retryTimer?.cancel();
    _generation++;
    _disposeAd();
    super.dispose();
  }

  /// Drops the current ad (if any) and loads a new one if allowed.
  void reload() {
    _generation++;
    _retryTimer?.cancel();
    final wasVisible = _loaded;
    _disposeAd();
    if (wasVisible && mounted) setState(() {});
    unawaited(_load(_generation));
  }

  Future<void> _load(int generation) async {
    if (!mounted || !manager.inlineAdsAllowed.value) return;
    final adUnitId = manager.inlineAdUnitId(format);
    if (adUnitId == null) return;
    try {
      final ad = await createAd(
        adUnitId,
        onLoaded: (ad) => _onLoaded(generation, ad),
        onFailed: (ad, error) => _onFailed(generation, ad, error),
        onPaid: manager.paidEventHandler(format),
      );
      if (ad == null) return;
      if (!mounted || generation != _generation) {
        unawaited(ad.dispose());
        return;
      }
      _ad = ad;
      manager.logger.info('${format.name}: loading…');
      await ad.load();
    } catch (e, st) {
      manager.logger.error('${format.name}: load threw', e, st);
      _scheduleRetry(generation);
    }
  }

  void _onLoaded(int generation, Ad ad) {
    if (!mounted || generation != _generation || !identical(ad, _ad)) {
      unawaited(ad.dispose());
      return;
    }
    _backoff.reset();
    final source =
        ad.responseInfo?.loadedAdapterResponseInfo?.adSourceName ?? 'unknown';
    manager.logger.info('${format.name}: loaded (source: $source)');
    setState(() => _loaded = true);
  }

  void _onFailed(int generation, Ad ad, LoadAdError error) {
    unawaited(ad.dispose());
    if (identical(ad, _ad)) _ad = null;
    if (!mounted || generation != _generation) return;
    manager.logger.error(
      '${format.name}: load failed (code ${error.code}: ${error.message})',
    );
    _scheduleRetry(generation);
  }

  void _scheduleRetry(int generation) {
    if (!mounted || generation != _generation) return;
    final delay = _backoff.nextDelay();
    manager.logger.info('${format.name}: retry in ${delay.inSeconds}s');
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (mounted && generation == _generation) unawaited(_load(generation));
    });
  }

  void _disposeAd() {
    final ad = _ad;
    _ad = null;
    _loaded = false;
    if (ad != null) {
      unawaited(ad.dispose().catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return buildLoaded(context, ad);
  }
}
