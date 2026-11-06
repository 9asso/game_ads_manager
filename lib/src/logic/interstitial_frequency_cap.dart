import '../ads_config.dart';
import 'clock.dart';

/// Result of asking [InterstitialFrequencyCap] whether an interstitial may be
/// shown now.
class FrequencyDecision {
  const FrequencyDecision._(this.allowed, this.reason);

  /// The interstitial may be shown.
  const FrequencyDecision.allow() : this._(true, 'allowed');

  /// The interstitial is blocked, with a human readable [reason].
  const FrequencyDecision.block(String reason) : this._(false, reason);

  /// Whether the interstitial may be shown.
  final bool allowed;

  /// Why (for logs).
  final String reason;

  @override
  String toString() => allowed ? 'allowed' : 'blocked: $reason';
}

/// Decides whether an interstitial may be shown, according to
/// [InterstitialRules].
///
/// Pure Dart with an injectable [Clock], so it is fully unit testable.
///
/// How "every N calls" works: every call to [evaluate] counts as one
/// opportunity (e.g. one level completed). An interstitial is allowed when at
/// least [InterstitialRules.showEveryNCalls] opportunities happened since the
/// last interstitial **and** all time rules pass. The counter is only reset by
/// [recordInterstitialShown], so if the ad was not loaded yet, the next
/// opportunity shows it.
class InterstitialFrequencyCap {
  /// Creates a cap. The "startup grace" period starts now (per [clock]).
  InterstitialFrequencyCap({required this.rules, Clock clock = systemClock})
    : _clock = clock,
      _startedAt = clock();

  /// Rules being enforced.
  final InterstitialRules rules;

  final Clock _clock;
  final DateTime _startedAt;
  DateTime? _lastInterstitialAt;
  DateTime? _lastRewardedAt;
  int _callsSinceLastShow = 0;

  /// Opportunities counted since the last interstitial was shown.
  int get callsSinceLastShow => _callsSinceLastShow;

  /// Counts one opportunity and returns whether an interstitial may be shown.
  FrequencyDecision evaluate() {
    _callsSinceLastShow++;
    return check();
  }

  /// Returns whether an interstitial may be shown, WITHOUT counting an
  /// opportunity.
  FrequencyDecision check() {
    final now = _clock();

    final sinceStart = now.difference(_startedAt);
    if (sinceStart < Duration(seconds: rules.startupGraceSeconds)) {
      return FrequencyDecision.block(
        'startup grace (${sinceStart.inSeconds}s < ${rules.startupGraceSeconds}s)',
      );
    }

    final lastRewarded = _lastRewardedAt;
    if (lastRewarded != null) {
      final since = now.difference(lastRewarded);
      if (since < Duration(seconds: rules.cooldownAfterRewardedSeconds)) {
        return FrequencyDecision.block(
          'rewarded cooldown (${since.inSeconds}s < '
          '${rules.cooldownAfterRewardedSeconds}s)',
        );
      }
    }

    final lastInterstitial = _lastInterstitialAt;
    if (lastInterstitial != null) {
      final since = now.difference(lastInterstitial);
      if (since < Duration(seconds: rules.minSecondsBetween)) {
        return FrequencyDecision.block(
          'min interval (${since.inSeconds}s < ${rules.minSecondsBetween}s)',
        );
      }
    }

    final everyN = rules.showEveryNCalls < 1 ? 1 : rules.showEveryNCalls;
    if (_callsSinceLastShow < everyN) {
      return FrequencyDecision.block('call $_callsSinceLastShow of $everyN');
    }

    return const FrequencyDecision.allow();
  }

  /// Call when an interstitial was actually shown. Resets the call counter and
  /// starts the minimum interval.
  void recordInterstitialShown() {
    _lastInterstitialAt = _clock();
    _callsSinceLastShow = 0;
  }

  /// Call when a rewarded ad was closed. Starts the post-rewarded cooldown.
  void recordRewardedShown() {
    _lastRewardedAt = _clock();
  }
}
