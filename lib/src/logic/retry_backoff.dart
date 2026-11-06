import 'dart:math' as math;

/// Exponential backoff for ad load retries: 2s, 4s, 8s, 16s, 32s, 60s, 60s…
///
/// Pure Dart (no Flutter, no timers) so it can be unit tested.
class RetryBackoff {
  /// Creates a backoff starting at [initialDelay], multiplied by [multiplier]
  /// after every failure, and never exceeding [maxDelay].
  RetryBackoff({
    this.initialDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(seconds: 60),
    this.multiplier = 2,
  }) : assert(multiplier >= 1, 'multiplier must be >= 1'),
       assert(initialDelay <= maxDelay, 'initialDelay must be <= maxDelay');

  /// Delay before the first retry.
  final Duration initialDelay;

  /// Upper bound for any delay.
  final Duration maxDelay;

  /// Growth factor applied after each failure.
  final double multiplier;

  int _failures = 0;

  /// Number of consecutive failures recorded since the last [reset].
  int get failures => _failures;

  /// Records a failure and returns how long to wait before the next attempt.
  Duration nextDelay() {
    final delay = peekDelay();
    _failures++;
    return delay;
  }

  /// The delay [nextDelay] would return, without recording a failure.
  Duration peekDelay() {
    final maxMs = maxDelay.inMilliseconds.toDouble();
    final ms =
        initialDelay.inMilliseconds *
        math.pow(multiplier, _failures).toDouble();
    // `ms` may be infinite after many failures; clamp handles that.
    return Duration(milliseconds: ms.clamp(0, maxMs).round());
  }

  /// Call after a successful load so the next failure starts from
  /// [initialDelay] again.
  void reset() => _failures = 0;
}
