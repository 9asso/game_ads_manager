import 'package:flutter/foundation.dart';

/// Prints `[GameAds]`-prefixed logs when enabled.
class AdsLogger {
  /// Whether logs are printed.
  bool enabled = true;

  /// Logs an informational message.
  void info(String message) {
    if (enabled) debugPrint('[GameAds] $message');
  }

  /// Logs a warning or error. Never throws.
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (!enabled) return;
    debugPrint('[GameAds] ⚠️ $message${error == null ? '' : ': $error'}');
    if (stackTrace != null && kDebugMode) {
      debugPrint(stackTrace.toString());
    }
  }
}
