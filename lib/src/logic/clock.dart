/// Returns the current time.
///
/// Injected into time-based logic so unit tests can control time.
typedef Clock = DateTime Function();

/// The real wall clock.
DateTime systemClock() => DateTime.now();
