/// The ad formats managed by this package.
enum AdFormat {
  /// Anchored adaptive banner.
  banner,

  /// Interstitial.
  interstitial,

  /// Rewarded video.
  rewarded,

  /// Rewarded interstitial.
  rewardedInterstitial,

  /// App open.
  appOpen,

  /// Native (template).
  native,
}

/// How accurate an [AdPaidEvent.valueMicros] is.
enum AdRevenuePrecision {
  /// Unknown precision.
  unknown,

  /// Estimated from aggregated data.
  estimated,

  /// Provided by the publisher (e.g. manual CPM in a mediation group).
  publisherProvided,

  /// The exact value paid for this impression.
  precise,
}

/// Revenue earned by one ad impression (impression-level ad revenue).
///
/// Send it to your analytics, e.g. Firebase `ad_impression`:
/// `value: event.valueMicros / 1e6, currency: event.currencyCode`.
class AdPaidEvent {
  /// Creates a paid event.
  const AdPaidEvent({
    required this.format,
    required this.adUnitId,
    required this.valueMicros,
    required this.currencyCode,
    required this.precision,
    this.placement,
  });

  /// Format of the ad that earned the revenue.
  final AdFormat format;

  /// Ad unit ID that served the ad.
  final String adUnitId;

  /// Revenue in micros (1,000,000 micros = 1 unit of [currencyCode]).
  final double valueMicros;

  /// ISO 4217 currency code, e.g. `USD`.
  final String currencyCode;

  /// Accuracy of [valueMicros].
  final AdRevenuePrecision precision;

  /// The placement passed to `showInterstitial(placement:)` and similar,
  /// if any.
  final String? placement;

  /// Revenue in currency units (micros / 1,000,000).
  double get value => valueMicros / 1000000;

  @override
  String toString() =>
      'AdPaidEvent(${format.name}, $adUnitId, $valueMicros $currencyCode '
      'micros, ${precision.name}${placement == null ? '' : ', $placement'})';
}
