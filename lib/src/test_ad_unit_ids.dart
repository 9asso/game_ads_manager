import 'ads_config.dart';

/// Google's official demo ad unit IDs.
///
/// Source: the `google_mobile_ads` 9.2.0 example app and
/// https://developers.google.com/admob/flutter/test-ads
/// These always return test ads and are safe to click.
abstract final class TestAdUnitIds {
  /// Android demo ad units.
  static const android = PlatformAdUnits(
    banner: 'ca-app-pub-3940256099942544/9214589741', // adaptive banner
    interstitial: 'ca-app-pub-3940256099942544/1033173712',
    rewarded: 'ca-app-pub-3940256099942544/5224354917',
    rewardedInterstitial: 'ca-app-pub-3940256099942544/5354046379',
    appOpen: 'ca-app-pub-3940256099942544/9257395921',
    native: 'ca-app-pub-3940256099942544/2247696110',
  );

  /// iOS demo ad units.
  static const ios = PlatformAdUnits(
    banner: 'ca-app-pub-3940256099942544/2435281174', // adaptive banner
    interstitial: 'ca-app-pub-3940256099942544/4411468910',
    rewarded: 'ca-app-pub-3940256099942544/1712485313',
    rewardedInterstitial: 'ca-app-pub-3940256099942544/6978759866',
    appOpen: 'ca-app-pub-3940256099942544/5575463023',
    native: 'ca-app-pub-3940256099942544/3986624511',
  );
}
