import '../logic/clock.dart';
import '../logic/interstitial_frequency_cap.dart' show FrequencyDecision;

/// Decides whether an app open ad may be shown when the app returns to the
/// foreground. Pure Dart with an injectable [Clock].
class AppOpenPolicy {
  /// Creates the policy.
  AppOpenPolicy({
    required this.cooldown,
    this.guardAfterFullScreen = const Duration(seconds: 30),
    Clock clock = systemClock,
  }) : _clock = clock;

  /// Minimum time between two app open ads.
  final Duration cooldown;

  /// No app open ad this soon after any other full-screen ad was closed
  /// (also covers returning from an ad click).
  final Duration guardAfterFullScreen;

  final Clock _clock;
  DateTime? _lastShownAt;

  /// Returns whether an app open ad may be shown now.
  FrequencyDecision check({
    required bool isFirstLaunch,
    required bool adsRemoved,
    required bool fullScreenAdShowing,
    DateTime? lastFullScreenDismissedAt,
  }) {
    if (adsRemoved) return const FrequencyDecision.block('ads removed');
    if (isFirstLaunch) {
      return const FrequencyDecision.block('first launch');
    }
    if (fullScreenAdShowing) {
      return const FrequencyDecision.block('another full-screen ad is open');
    }
    final now = _clock();
    if (lastFullScreenDismissedAt != null &&
        now.difference(lastFullScreenDismissedAt) < guardAfterFullScreen) {
      return const FrequencyDecision.block('right after another ad');
    }
    final last = _lastShownAt;
    if (last != null && now.difference(last) < cooldown) {
      return const FrequencyDecision.block('cooldown');
    }
    return const FrequencyDecision.allow();
  }

  /// Call when an app open ad was shown.
  void recordShown() => _lastShownAt = _clock();
}
