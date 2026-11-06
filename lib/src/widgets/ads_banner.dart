import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_paid_event.dart';
import 'inline_ad_state.dart';

/// An anchored adaptive banner sized to the screen width.
///
/// * Takes no space until an ad is loaded.
/// * Shows nothing if banners are disabled (no banner ID), consent does not
///   allow ads, or `setAdsRemoved(true)` was called.
/// * Reloads when the screen width changes (rotation).
///
/// Put it at the bottom of your menu screens, e.g.
/// `Scaffold(bottomNavigationBar: const SafeArea(child: AdsBanner()))`.
class AdsBanner extends StatefulWidget {
  /// Creates a banner.
  const AdsBanner({super.key});

  @override
  State<AdsBanner> createState() => _AdsBannerState();
}

class _AdsBannerState extends InlineAdState<AdsBanner, BannerAd> {
  int? _width;

  @override
  AdFormat get format => AdFormat.banner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width > 0 && width != _width) {
      _width = width;
      reload();
    }
  }

  @override
  Future<BannerAd?> createAd(
    String adUnitId, {
    required void Function(Ad ad) onLoaded,
    required void Function(Ad ad, LoadAdError error) onFailed,
    required OnPaidEventCallback onPaid,
  }) async {
    final width = _width;
    if (width == null) return null;
    AdSize size = AdSize.banner;
    try {
      size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width) ?? size;
    } catch (e) {
      manager.logger.error('banner: adaptive size failed, using 320x50', e);
    }
    return BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
        onPaidEvent: onPaid,
      ),
    );
  }

  @override
  Widget buildLoaded(BuildContext context, BannerAd ad) {
    return Align(
      heightFactor: 1,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
