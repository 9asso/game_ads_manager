/// Ad unit IDs for ONE platform (Android or iOS).
///
/// Any format left `null` is disabled on that platform.
class PlatformAdUnits {
  /// Creates the ad unit IDs for one platform.
  const PlatformAdUnits({
    this.banner,
    this.interstitial,
    this.rewarded,
    this.rewardedInterstitial,
    this.appOpen,
    this.native,
  });

  /// Anchored adaptive banner ad unit ID.
  final String? banner;

  /// Interstitial ad unit ID.
  final String? interstitial;

  /// Rewarded ad unit ID.
  final String? rewarded;

  /// Rewarded interstitial ad unit ID (optional format).
  final String? rewardedInterstitial;

  /// App open ad unit ID (optional format, shown when the app returns from
  /// the background).
  final String? appOpen;

  /// Native ad unit ID (rendered with Google's native templates).
  final String? native;
}

/// Rules that limit how often interstitials appear.
///
/// All rules must pass for an interstitial to be shown.
class InterstitialRules {
  /// Creates interstitial frequency rules. Defaults suit most casual games.
  const InterstitialRules({
    this.minSecondsBetween = 60,
    this.showEveryNCalls = 2,
    this.startupGraceSeconds = 30,
    this.cooldownAfterRewardedSeconds = 30,
  });

  /// Minimum seconds between two interstitials.
  final int minSecondsBetween;

  /// Show only on every N-th call to `showInterstitial()`
  /// (e.g. 2 = every second level completion). Values below 1 count as 1.
  final int showEveryNCalls;

  /// No interstitial during the first X seconds after `initialize()`.
  final int startupGraceSeconds;

  /// No interstitial within X seconds after a rewarded ad was closed.
  final int cooldownAfterRewardedSeconds;
}

/// Maximum ad content rating (maps to AdMob's `MaxAdContentRating`).
enum AdContentRating {
  /// General audiences.
  g,

  /// Parental guidance.
  pg,

  /// Teen.
  t,

  /// Mature audiences.
  ma,
}

/// Everything a game passes to `AdsManager.instance.initialize()`.
class AdsConfig {
  /// Creates the ads configuration for one game.
  const AdsConfig({
    this.android = const PlatformAdUnits(),
    this.ios = const PlatformAdUnits(),
    this.testMode,
    this.testDeviceIds = const [],
    this.tagForChildDirectedTreatment,
    this.tagForUnderAgeOfConsent,
    this.maxAdContentRating,
    this.interstitialRules = const InterstitialRules(),
    this.appOpenCooldown = const Duration(hours: 4),
    this.attPromptDelay = const Duration(seconds: 1),
    this.usPrivacyOptOut,
    this.debugConsentAsEea = false,
    this.enableLogging = true,
  });

  /// Android ad unit IDs.
  final PlatformAdUnits android;

  /// iOS ad unit IDs.
  final PlatformAdUnits ios;

  /// Whether to use Google's official TEST ad unit IDs.
  ///
  /// * `null` (default): test IDs in debug builds, real IDs in release.
  /// * `true`: always test IDs.
  /// * `false`: always real IDs, even in debug. Use this together with
  ///   [testDeviceIds] to test mediation networks with Ad Inspector.
  final bool? testMode;

  /// Devices that receive test ads even with real ad unit IDs.
  ///
  /// Find your ID in the device log after the first ad request
  /// (look for "setTestDeviceIds" / "testDeviceIdentifiers").
  final List<String> testDeviceIds;

  /// Tag ad requests as child-directed (COPPA). `null` = unspecified.
  final bool? tagForChildDirectedTreatment;

  /// Tag users as under the age of consent (GDPR). `null` = unspecified.
  final bool? tagForUnderAgeOfConsent;

  /// Maximum content rating of ads. `null` = AdMob default.
  final AdContentRating? maxAdContentRating;

  /// Interstitial frequency rules.
  final InterstitialRules interstitialRules;

  /// Minimum time between two app open ads.
  final Duration appOpenCooldown;

  /// Delay before the iOS App Tracking Transparency prompt, so it does not
  /// appear during the launch animation.
  final Duration attPromptDelay;

  /// US state privacy laws (CCPA etc.): `true` if the user opted out of the
  /// "sale" of personal information, `false` if not, `null` to send nothing.
  ///
  /// Forwarded to ironSource, AppLovin, Unity Ads and Liftoff Monetize
  /// before the SDK starts. GDPR consent is NOT forwarded manually: every
  /// adapter reads it automatically from the Google UMP consent form.
  final bool? usPrivacyOptOut;

  /// Pretend this device is in the EEA so the GDPR consent form appears.
  ///
  /// Only works on devices listed in [testDeviceIds] and is ignored in
  /// release builds. Handy for testing the "Privacy settings" button.
  final bool debugConsentAsEea;

  /// Print `[GameAds]` logs.
  final bool enableLogging;
}
