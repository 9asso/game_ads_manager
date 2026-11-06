/// AdMob mediation (real-time bidding) for Flutter games, in a few lines.
///
/// ```dart
/// await AdsManager.instance.initialize(const AdsConfig(
///   android: PlatformAdUnits(rewarded: '...', interstitial: '...'),
///   ios: PlatformAdUnits(rewarded: '...', interstitial: '...'),
/// ));
/// ```
library;

export 'src/ad_paid_event.dart';
export 'src/ads_config.dart';
export 'src/ads_manager.dart' show AdsManager;
export 'src/widgets/ads_banner.dart';
export 'src/widgets/ads_native.dart';
