import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_paid_event.dart';
import 'ads_config.dart';
import 'ads_logger.dart';
import 'app_open/app_open_policy.dart';
import 'consent/consent_manager.dart';
import 'loaders/full_screen_ad_slot.dart';
import 'logic/interstitial_frequency_cap.dart';
import 'test_ad_unit_ids.dart';

/// The single entry point of the package.
///
/// ```dart
/// await AdsManager.instance.initialize(AdsConfig(...));
/// final earned = await AdsManager.instance.showRewarded();
/// await AdsManager.instance.showInterstitial(placement: 'level_end');
/// ```
///
/// Nothing in this class ever throws: every ad error is logged and the game
/// continues normally.
class AdsManager {
  AdsManager._();

  /// The shared instance.
  static final AdsManager instance = AdsManager._();

  static const _firstLaunchKey = 'game_ads_manager.has_launched';
  static const _showCallbackTimeout = Duration(seconds: 10);
  static const _rewardGrace = Duration(milliseconds: 600);

  final AdsLogger _log = AdsLogger();
  late final ConsentManager _consent = ConsentManager(_log);

  AdsConfig _config = const AdsConfig();
  PlatformAdUnits _units = const PlatformAdUnits();
  InterstitialFrequencyCap? _cap;
  AppOpenPolicy? _appOpenPolicy;

  Future<void>? _initFuture;
  Future<void>? _sdkStartFuture;
  bool _initialized = false;
  bool _sdkStarted = false;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;
  bool _adsRemoved = false;
  bool _isFirstLaunch = true;
  bool _fullScreenShowing = false;
  DateTime? _lastFullScreenDismissedAt;

  FullScreenAdSlot<InterstitialAd>? _interstitial;
  FullScreenAdSlot<RewardedAd>? _rewarded;
  FullScreenAdSlot<RewardedInterstitialAd>? _rewardedInterstitial;
  FullScreenAdSlot<AppOpenAd>? _appOpen;
  // Lives as long as the app (singleton), so it is never cancelled.
  // ignore: cancel_subscriptions
  StreamSubscription<AppState>? _appStateSub;

  final ValueNotifier<bool> _rewardedReady = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _rewardedInterstitialReady = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<bool> _inlineAdsAllowed = ValueNotifier<bool>(false);

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  /// Called when a full-screen ad (interstitial, rewarded, app open…) appears.
  /// Pause your music and gameplay here.
  VoidCallback? onFullScreenAdShow;

  /// Called when a full-screen ad is closed. Resume music and gameplay here.
  VoidCallback? onFullScreenAdDismiss;

  /// Called for every impression that earned revenue (all formats).
  void Function(AdPaidEvent event)? onPaidEvent;

  // ---------------------------------------------------------------------------
  // Setup
  // ---------------------------------------------------------------------------

  /// Runs the full startup sequence:
  ///
  /// 1. Google UMP consent (shows the GDPR form if required).
  /// 2. iOS App Tracking Transparency prompt (after a short delay).
  /// 3. `MobileAds.initialize()` — only if consent allows ads.
  /// 4. Preloads interstitial and rewarded ads.
  ///
  /// Safe to call more than once (later calls return the first call's
  /// future). Never throws. Unsupported platforms (web, desktop) do nothing.
  Future<void> initialize(AdsConfig config) =>
      _initFuture ??= _initialize(config);

  Future<void> _initialize(AdsConfig config) async {
    _config = config;
    _log.enabled = config.enableLogging;
    try {
      if (!_isSupportedPlatform) {
        _log.info('Unsupported platform – ads disabled');
        return;
      }
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      final useTestIds = config.testMode ?? kDebugMode;
      _units = useTestIds
          ? (isIOS ? TestAdUnitIds.ios : TestAdUnitIds.android)
          : (isIOS ? config.ios : config.android);
      _log.info(
        'initialize: ${isIOS ? 'iOS' : 'Android'}, '
        '${useTestIds ? 'TEST ad units' : 'REAL ad units'}, '
        'formats: ${_enabledFormats().join(', ')}',
      );

      _cap = InterstitialFrequencyCap(rules: config.interstitialRules);
      _appOpenPolicy = AppOpenPolicy(cooldown: config.appOpenCooldown);
      _isFirstLaunch = await _checkFirstLaunch();

      // 1. GDPR consent.
      await _consent.gatherConsent(
        tagForUnderAgeOfConsent: config.tagForUnderAgeOfConsent,
        debugAsEea: config.debugConsentAsEea,
        testDeviceIds: config.testDeviceIds,
      );
      _privacyOptionsRequired = await _consent.isPrivacyOptionsRequired();

      // 2. ATT (iOS only, after UMP).
      if (isIOS) {
        await _consent.requestTrackingAuthorization(config.attPromptDelay);
      }

      // 3 + 4. Start the SDK and preload.
      await _startSdkIfAllowed();
    } catch (e, st) {
      _log.error('initialize failed', e, st);
    } finally {
      _initialized = true;
    }
  }

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  List<String> _enabledFormats() => [
    if (_units.banner != null) 'banner',
    if (_units.interstitial != null) 'interstitial',
    if (_units.rewarded != null) 'rewarded',
    if (_units.rewardedInterstitial != null) 'rewardedInterstitial',
    if (_units.appOpen != null) 'appOpen',
    if (_units.native != null) 'native',
  ];

  Future<bool> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasLaunched = prefs.getBool(_firstLaunchKey) ?? false;
      if (!hasLaunched) await prefs.setBool(_firstLaunchKey, true);
      return !hasLaunched;
    } catch (e, st) {
      _log.error('first-launch check failed', e, st);
      return false;
    }
  }

  Future<void> _startSdkIfAllowed() =>
      _sdkStartFuture ??= _startSdk().whenComplete(() {
        // Allow a retry later (e.g. after the privacy form) if not started.
        if (!_sdkStarted) _sdkStartFuture = null;
      });

  Future<void> _startSdk() async {
    if (_sdkStarted) return;
    try {
      _canRequestAds = await _consent.canRequestAds();
      if (!_canRequestAds) {
        _log.info('Consent does not allow ads (yet) – SDK not started');
        return;
      }

      final usOptOut = _config.usPrivacyOptOut;
      if (usOptOut != null) {
        await _consent.forwardUsPrivacy(optOut: usOptOut);
      }

      await MobileAds.instance.updateRequestConfiguration(
        _requestConfiguration(),
      );

      final status = await MobileAds.instance.initialize().timeout(
        const Duration(seconds: 15),
      );
      status.adapterStatuses.forEach((name, s) {
        _log.info(
          'adapter $name: ${s.state.name}'
          '${s.description.isEmpty ? '' : ' (${s.description})'}',
        );
      });
    } on TimeoutException {
      // Some adapters are slow; the SDK keeps initializing in the background
      // and ad loads still work.
      _log.info('MobileAds.initialize() is slow – continuing anyway');
    } catch (e, st) {
      _log.error('MobileAds start failed', e, st);
      return;
    }
    if (!_canRequestAds) return;

    _sdkStarted = true;
    _log.info('MobileAds started');
    _createFullScreenSlots();
    _listenForAppOpen();
    _refreshInlineAllowed();
  }

  RequestConfiguration _requestConfiguration() {
    int tri(bool? v) => switch (v) {
      true => 1,
      false => 0,
      null => -1,
    };
    final rating = switch (_config.maxAdContentRating) {
      AdContentRating.g => MaxAdContentRating.g,
      AdContentRating.pg => MaxAdContentRating.pg,
      AdContentRating.t => MaxAdContentRating.t,
      AdContentRating.ma => MaxAdContentRating.ma,
      null => null,
    };
    return RequestConfiguration(
      testDeviceIds: _config.testDeviceIds,
      maxAdContentRating: rating,
      // The legacy tags are still read by mediation adapters (Unity, AppLovin…)
      // so we send them in addition to the newer ageRestrictedTreatment.
      // ignore: deprecated_member_use
      tagForChildDirectedTreatment: tri(_config.tagForChildDirectedTreatment),
      // ignore: deprecated_member_use
      tagForUnderAgeOfConsent: tri(_config.tagForUnderAgeOfConsent),
      ageRestrictedTreatment: _config.tagForChildDirectedTreatment == true
          ? AgeRestrictedTreatment.child
          : null,
    );
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// Whether [initialize] has completed (successfully or not).
  bool get isInitialized => _initialized;

  /// Whether the user's consent allows requesting ads.
  bool get canRequestAds => _canRequestAds;

  /// Whether a "Privacy settings" button must be shown in your settings menu
  /// (GDPR). Show it only when this is `true`.
  bool get isPrivacyOptionsRequired => _privacyOptionsRequired;

  /// Whether the "remove ads" purchase is active.
  bool get adsRemoved => _adsRemoved;

  // ---------------------------------------------------------------------------
  // Rewarded
  // ---------------------------------------------------------------------------

  /// Whether a rewarded ad is loaded and ready.
  bool get isRewardedReady => _rewarded?.isReady ?? false;

  /// Notifies when [isRewardedReady] changes. Use it to enable/disable
  /// "Watch video" buttons with a `ValueListenableBuilder`.
  ValueListenable<bool> get rewardedReadyNotifier => _rewardedReady;

  /// Shows a rewarded ad. Returns `true` ONLY if the user earned the reward.
  ///
  /// Returns `false` immediately if no ad is ready. Rewarded ads stay
  /// available after [setAdsRemoved] because players choose to watch them.
  Future<bool> showRewarded({String? placement}) async {
    final slot = _rewarded;
    if (!_sdkStarted || slot == null) {
      _log.info('rewarded: not available');
      return false;
    }
    return _present(slot, AdFormat.rewarded, placement: placement);
  }

  /// Whether a rewarded interstitial is loaded and ready.
  bool get isRewardedInterstitialReady =>
      _rewardedInterstitial?.isReady ?? false;

  /// Notifies when [isRewardedInterstitialReady] changes.
  ValueListenable<bool> get rewardedInterstitialReadyNotifier =>
      _rewardedInterstitialReady;

  /// Shows a rewarded interstitial. Returns `true` only if the reward was
  /// earned; `false` immediately if none is ready.
  Future<bool> showRewardedInterstitial({String? placement}) async {
    final slot = _rewardedInterstitial;
    if (!_sdkStarted || slot == null) {
      _log.info('rewardedInterstitial: not available');
      return false;
    }
    return _present(slot, AdFormat.rewardedInterstitial, placement: placement);
  }

  // ---------------------------------------------------------------------------
  // Interstitial
  // ---------------------------------------------------------------------------

  /// Call at every natural break (e.g. level completed). Shows an
  /// interstitial only if the frequency rules allow it and one is loaded;
  /// otherwise does nothing.
  ///
  /// The returned future completes when the ad is closed (or immediately if
  /// nothing was shown), so you can `await` it before continuing.
  Future<void> showInterstitial({String? placement}) async {
    final slot = _interstitial;
    final cap = _cap;
    if (!_sdkStarted || _adsRemoved || slot == null || cap == null) return;
    final decision = cap.evaluate();
    final where = placement == null ? '' : ' [$placement]';
    if (!decision.allowed) {
      _log.info('interstitial$where skipped: ${decision.reason}');
      return;
    }
    if (!slot.isReady) {
      _log.info('interstitial$where not loaded yet – will show next time');
      slot.take(); // makes sure a load is in progress
      return;
    }
    await _present(slot, AdFormat.interstitial, placement: placement);
  }

  // ---------------------------------------------------------------------------
  // Remove ads, privacy, debug
  // ---------------------------------------------------------------------------

  /// Enables/disables the "remove ads" purchase. When `true`, interstitials,
  /// banners, native ads and app open ads stop; rewarded ads stay available.
  ///
  /// Not persisted: call it at every startup from your purchase state.
  void setAdsRemoved(bool removed) {
    if (_adsRemoved == removed) return;
    _adsRemoved = removed;
    _log.info('ads removed: $removed');
    try {
      if (removed) {
        _interstitial?.dispose();
        _interstitial = null;
        _appOpen?.dispose();
        _appOpen = null;
      } else if (_sdkStarted) {
        _createFullScreenSlots();
      }
    } catch (e, st) {
      _log.error('setAdsRemoved failed', e, st);
    }
    _refreshInlineAllowed();
  }

  /// Shows the UMP privacy options form (for your "Privacy settings" button).
  /// Starts the ads SDK afterwards if consent now allows it.
  Future<void> showPrivacyOptionsForm() async {
    if (!_isSupportedPlatform) return;
    await _consent.showPrivacyOptionsForm();
    _privacyOptionsRequired = await _consent.isPrivacyOptionsRequired();
    _canRequestAds = await _consent.canRequestAds();
    if (_canRequestAds && !_sdkStarted && _initialized) {
      await _startSdkIfAllowed();
    }
  }

  /// Opens Google's Ad Inspector to check mediation, adapters and bidding.
  ///
  /// Works on test devices (see [AdsConfig.testDeviceIds]) and emulators.
  Future<void> openAdInspector() async {
    if (!_isSupportedPlatform) return;
    final completer = Completer<void>();
    try {
      // The error type is not exported by google_mobile_ads; it is inferred.
      MobileAds.instance.openAdInspector((error) {
        if (error != null) {
          _log.error('Ad Inspector: ${error.code}', error.message);
        }
        if (!completer.isCompleted) completer.complete();
      });
    } catch (e, st) {
      _log.error('openAdInspector failed', e, st);
      if (!completer.isCompleted) completer.complete();
    }
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Internal: used by AdsBanner / AdsNative
  // ---------------------------------------------------------------------------

  /// Whether banner/native widgets may load ads (SDK started, ads not
  /// removed).
  @internal
  ValueListenable<bool> get inlineAdsAllowed => _inlineAdsAllowed;

  /// Ad unit ID for an inline format, or `null` if disabled.
  @internal
  String? inlineAdUnitId(AdFormat format) => switch (format) {
    AdFormat.banner => _units.banner,
    AdFormat.native => _units.native,
    _ => null,
  };

  /// Package logger.
  @internal
  AdsLogger get logger => _log;

  /// Builds an `OnPaidEventCallback` that forwards to [onPaidEvent].
  @internal
  OnPaidEventCallback paidEventHandler(AdFormat format, {String? placement}) {
    return (
      Ad ad,
      double valueMicros,
      PrecisionType precision,
      String currencyCode,
    ) {
      final event = AdPaidEvent(
        format: format,
        adUnitId: ad.adUnitId,
        valueMicros: valueMicros,
        currencyCode: currencyCode,
        precision: switch (precision) {
          PrecisionType.estimated => AdRevenuePrecision.estimated,
          PrecisionType.publisherProvided =>
            AdRevenuePrecision.publisherProvided,
          PrecisionType.precise => AdRevenuePrecision.precise,
          PrecisionType.unknown => AdRevenuePrecision.unknown,
        },
        placement: placement,
      );
      _log.info('paid: $event');
      _safeCall(() => onPaidEvent?.call(event), 'onPaidEvent');
    };
  }

  // ---------------------------------------------------------------------------
  // Internal: full-screen ads
  // ---------------------------------------------------------------------------

  void _createFullScreenSlots() {
    const request = AdRequest();

    final rewardedId = _units.rewarded;
    if (rewardedId != null && _rewarded == null) {
      _rewarded = FullScreenAdSlot<RewardedAd>(
        format: AdFormat.rewarded,
        adUnitId: rewardedId,
        logger: _log,
        readyNotifier: _rewardedReady,
        loader: ({required adUnitId, required onLoaded, required onFailed}) =>
            RewardedAd.load(
              adUnitId: adUnitId,
              request: request,
              rewardedAdLoadCallback: RewardedAdLoadCallback(
                onAdLoaded: onLoaded,
                onAdFailedToLoad: onFailed,
              ),
            ),
      )..load();
    }

    final rewardedInterstitialId = _units.rewardedInterstitial;
    if (rewardedInterstitialId != null && _rewardedInterstitial == null) {
      _rewardedInterstitial = FullScreenAdSlot<RewardedInterstitialAd>(
        format: AdFormat.rewardedInterstitial,
        adUnitId: rewardedInterstitialId,
        logger: _log,
        readyNotifier: _rewardedInterstitialReady,
        loader: ({required adUnitId, required onLoaded, required onFailed}) =>
            RewardedInterstitialAd.load(
              adUnitId: adUnitId,
              request: request,
              rewardedInterstitialAdLoadCallback:
                  RewardedInterstitialAdLoadCallback(
                    onAdLoaded: onLoaded,
                    onAdFailedToLoad: onFailed,
                  ),
            ),
      )..load();
    }

    if (_adsRemoved) return;

    final interstitialId = _units.interstitial;
    if (interstitialId != null && _interstitial == null) {
      _interstitial = FullScreenAdSlot<InterstitialAd>(
        format: AdFormat.interstitial,
        adUnitId: interstitialId,
        logger: _log,
        loader: ({required adUnitId, required onLoaded, required onFailed}) =>
            InterstitialAd.load(
              adUnitId: adUnitId,
              request: request,
              adLoadCallback: InterstitialAdLoadCallback(
                onAdLoaded: onLoaded,
                onAdFailedToLoad: onFailed,
              ),
            ),
      )..load();
    }

    final appOpenId = _units.appOpen;
    if (appOpenId != null && _appOpen == null) {
      _appOpen = FullScreenAdSlot<AppOpenAd>(
        format: AdFormat.appOpen,
        adUnitId: appOpenId,
        logger: _log,
        loader: ({required adUnitId, required onLoaded, required onFailed}) =>
            AppOpenAd.load(
              adUnitId: adUnitId,
              request: request,
              adLoadCallback: AppOpenAdLoadCallback(
                onAdLoaded: onLoaded,
                onAdFailedToLoad: onFailed,
              ),
            ),
      )..load();
    }
  }

  /// Shows the ad held by [slot]. Returns `true` if the ad was shown (and,
  /// for rewarded formats, the reward was earned).
  Future<bool> _present<T extends AdWithoutView>(
    FullScreenAdSlot<T> slot,
    AdFormat format, {
    String? placement,
  }) async {
    if (_fullScreenShowing) {
      _log.info('${format.name}: another full-screen ad is open');
      return false;
    }
    final ad = slot.take();
    if (ad == null) {
      _log.info('${format.name}: not ready');
      return false;
    }

    final isRewardFormat =
        format == AdFormat.rewarded || format == AdFormat.rewardedInterstitial;
    final completer = Completer<bool>();
    var shown = false;
    var earned = false;
    Timer? showTimeout;
    _fullScreenShowing = true;

    void finish() {
      if (completer.isCompleted) return;
      showTimeout?.cancel();
      _fullScreenShowing = false;
      _lastFullScreenDismissedAt = DateTime.now();
      unawaited(ad.dispose().catchError((Object _) {}));
      if (shown) {
        if (isRewardFormat) _cap?.recordRewardedShown();
        _safeCall(() => onFullScreenAdDismiss?.call(), 'onFullScreenAdDismiss');
      }
      slot.load(); // keep the next one ready
      final result = isRewardFormat ? earned : shown;
      _log.info(
        '${format.name}: closed${isRewardFormat ? ' (reward earned: $earned)' : ''}',
      );
      completer.complete(result);
    }

    void onShowed() {
      shown = true;
      showTimeout?.cancel();
      _log.info('${format.name}: showing');
      if (format == AdFormat.interstitial) _cap?.recordInterstitialShown();
      if (format == AdFormat.appOpen) _appOpenPolicy?.recordShown();
      _safeCall(() => onFullScreenAdShow?.call(), 'onFullScreenAdShow');
    }

    void onDismissed() {
      if (isRewardFormat && !earned) {
        // Some networks report the reward right after the close event.
        Timer(_rewardGrace, finish);
      } else {
        finish();
      }
    }

    void onFailedToShow(AdError error) {
      _log.error('${format.name}: failed to show', error.message);
      finish();
    }

    try {
      ad.onPaidEvent = paidEventHandler(format, placement: placement);
      _attachCallbacks(ad, onShowed, onDismissed, onFailedToShow);
      showTimeout = Timer(_showCallbackTimeout, () {
        if (!shown) {
          _log.error('${format.name}: no show callback, giving up');
          finish();
        }
      });
      switch (ad) {
        case final RewardedAd a:
          await a.show(
            onUserEarnedReward: (_, reward) {
              earned = true;
              _log.info('reward earned: ${reward.amount} ${reward.type}');
            },
          );
        case final RewardedInterstitialAd a:
          await a.show(
            onUserEarnedReward: (_, reward) {
              earned = true;
              _log.info('reward earned: ${reward.amount} ${reward.type}');
            },
          );
        case final InterstitialAd a:
          await a.show();
        case final AppOpenAd a:
          await a.show();
        default:
          throw StateError('unsupported ad type ${ad.runtimeType}');
      }
    } catch (e, st) {
      _log.error('${format.name}: show threw', e, st);
      finish();
    }
    return completer.future;
  }

  void _attachCallbacks(
    Ad ad,
    void Function() onShowed,
    void Function() onDismissed,
    void Function(AdError error) onFailedToShow,
  ) {
    FullScreenContentCallback<A> callback<A extends Ad>() =>
        FullScreenContentCallback<A>(
          onAdShowedFullScreenContent: (_) => onShowed(),
          onAdDismissedFullScreenContent: (_) => onDismissed(),
          onAdFailedToShowFullScreenContent: (_, error) =>
              onFailedToShow(error),
        );
    switch (ad) {
      case final RewardedAd a:
        a.fullScreenContentCallback = callback<RewardedAd>();
      case final RewardedInterstitialAd a:
        a.fullScreenContentCallback = callback<RewardedInterstitialAd>();
      case final InterstitialAd a:
        a.fullScreenContentCallback = callback<InterstitialAd>();
      case final AppOpenAd a:
        a.fullScreenContentCallback = callback<AppOpenAd>();
    }
  }

  // ---------------------------------------------------------------------------
  // Internal: app open
  // ---------------------------------------------------------------------------

  void _listenForAppOpen() {
    if (_units.appOpen == null || _appStateSub != null) return;
    try {
      unawaited(
        AppStateEventNotifier.startListening().catchError((Object e) {
          _log.error('AppStateEventNotifier failed', e);
        }),
      );
      _appStateSub = AppStateEventNotifier.appStateStream.listen((state) {
        if (state == AppState.foreground) unawaited(_maybeShowAppOpen());
      }, onError: (Object e) => _log.error('app state stream error', e));
    } catch (e, st) {
      _log.error('app open listener failed', e, st);
    }
  }

  Future<void> _maybeShowAppOpen() async {
    final slot = _appOpen;
    final policy = _appOpenPolicy;
    if (slot == null || policy == null) return;
    final decision = policy.check(
      isFirstLaunch: _isFirstLaunch,
      adsRemoved: _adsRemoved,
      fullScreenAdShowing: _fullScreenShowing,
      lastFullScreenDismissedAt: _lastFullScreenDismissedAt,
    );
    if (!decision.allowed) {
      _log.info('appOpen skipped: ${decision.reason}');
      return;
    }
    await _present(slot, AdFormat.appOpen);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _refreshInlineAllowed() {
    _inlineAdsAllowed.value = _sdkStarted && !_adsRemoved;
  }

  void _safeCall(void Function() fn, String label) {
    try {
      fn();
    } catch (e, st) {
      _log.error('your $label callback threw', e, st);
    }
  }
}
