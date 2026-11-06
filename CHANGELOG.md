# Changelog

## 1.0.0

Initial release.

- `AdsManager` singleton with a single `initialize(AdsConfig)` call:
  Google UMP consent → iOS ATT prompt → `MobileAds.initialize()` → preloading.
- Rewarded (`showRewarded`, `isRewardedReady`, `rewardedReadyNotifier`),
  rewarded interstitial, interstitial with frequency cap, optional app open ads.
- `AdsBanner` (large anchored adaptive banner) and `AdsNative` (native templates).
- Exponential backoff retries (2s → 60s) and 55-minute ad expiry.
- `onFullScreenAdShow` / `onFullScreenAdDismiss` callbacks for game audio.
- `setAdsRemoved` for a "remove ads" purchase (rewarded stays available).
- `onPaidEvent` impression-level revenue callback.
- `showPrivacyOptionsForm`, `isPrivacyOptionsRequired`, `openAdInspector`.
- US privacy ("do not sell") forwarding to ironSource, AppLovin, Unity Ads and
  Liftoff Monetize.
- Bundled mediation adapters: Unity Ads, ironSource, Meta Audience Network,
  AppLovin, Mintegral, Pangle, Liftoff Monetize.
- Built on `google_mobile_ads` 9.2.0.
