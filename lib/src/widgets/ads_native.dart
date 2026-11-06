import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ad_paid_event.dart';
import 'inline_ad_state.dart';

/// Size of an [AdsNative] ad (Google native templates).
enum AdsNativeSize {
  /// Compact row (icon, headline, button). 90–200 px high.
  small,

  /// Card with media (image/video). 320–400 px high.
  medium,
}

/// A native ad rendered with Google's native templates — no native (Kotlin /
/// Swift) code needed in your game.
///
/// * Takes no space until an ad is loaded.
/// * Shows nothing if native ads are disabled (no native ID), consent does
///   not allow ads, or `setAdsRemoved(true)` was called.
///
/// Use it on menus, level-complete or game-over screens — never on top of
/// gameplay.
class AdsNative extends StatefulWidget {
  /// Creates a native ad. Colors default to the template's light theme.
  const AdsNative({
    super.key,
    this.size = AdsNativeSize.medium,
    this.backgroundColor,
    this.textColor,
    this.buttonColor,
    this.buttonTextColor,
    this.cornerRadius = 12,
  });

  /// Template size.
  final AdsNativeSize size;

  /// Background of the ad.
  final Color? backgroundColor;

  /// Headline and body text color.
  final Color? textColor;

  /// Call-to-action button background.
  final Color? buttonColor;

  /// Call-to-action button text color.
  final Color? buttonTextColor;

  /// Corner radius of the ad card.
  final double cornerRadius;

  @override
  State<AdsNative> createState() => _AdsNativeState();
}

class _AdsNativeState extends InlineAdState<AdsNative, NativeAd> {
  @override
  AdFormat get format => AdFormat.native;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void didUpdateWidget(AdsNative oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The style is baked into the ad at load time.
    if (oldWidget.size != widget.size ||
        oldWidget.backgroundColor != widget.backgroundColor ||
        oldWidget.textColor != widget.textColor ||
        oldWidget.buttonColor != widget.buttonColor ||
        oldWidget.buttonTextColor != widget.buttonTextColor ||
        oldWidget.cornerRadius != widget.cornerRadius) {
      reload();
    }
  }

  @override
  Future<NativeAd?> createAd(
    String adUnitId, {
    required void Function(Ad ad) onLoaded,
    required void Function(Ad ad, LoadAdError error) onFailed,
    required OnPaidEventCallback onPaid,
  }) async {
    final text = NativeTemplateTextStyle(textColor: widget.textColor);
    return NativeAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
        onPaidEvent: onPaid,
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: widget.size == AdsNativeSize.small
            ? TemplateType.small
            : TemplateType.medium,
        mainBackgroundColor: widget.backgroundColor,
        cornerRadius: widget.cornerRadius,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: widget.buttonTextColor,
          backgroundColor: widget.buttonColor,
        ),
        primaryTextStyle: text,
        secondaryTextStyle: text,
        tertiaryTextStyle: text,
      ),
    );
  }

  @override
  Widget buildLoaded(BuildContext context, NativeAd ad) {
    // Sizes recommended by Google for native templates.
    final constraints = widget.size == AdsNativeSize.small
        ? const BoxConstraints(
            minWidth: 320,
            minHeight: 90,
            maxWidth: 400,
            maxHeight: 200,
          )
        : const BoxConstraints(
            minWidth: 320,
            minHeight: 320,
            maxWidth: 400,
            maxHeight: 400,
          );
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: constraints,
        child: AdWidget(ad: ad),
      ),
    );
  }
}
