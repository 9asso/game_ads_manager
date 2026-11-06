import 'package:flutter_test/flutter_test.dart';
import 'package:game_ads_manager/src/logic/retry_backoff.dart';

void main() {
  group('RetryBackoff', () {
    test('doubles from 2s and caps at 60s', () {
      final backoff = RetryBackoff();
      final delays = List.generate(8, (_) => backoff.nextDelay().inSeconds);
      expect(delays, [2, 4, 8, 16, 32, 60, 60, 60]);
      expect(backoff.failures, 8);
    });

    test('reset starts over from the initial delay', () {
      final backoff = RetryBackoff()
        ..nextDelay()
        ..nextDelay()
        ..nextDelay();
      backoff.reset();
      expect(backoff.failures, 0);
      expect(backoff.nextDelay(), const Duration(seconds: 2));
    });

    test('peekDelay does not count a failure', () {
      final backoff = RetryBackoff();
      expect(backoff.peekDelay(), const Duration(seconds: 2));
      expect(backoff.peekDelay(), const Duration(seconds: 2));
      expect(backoff.failures, 0);
    });

    test('never overflows after very many failures', () {
      final backoff = RetryBackoff();
      for (var i = 0; i < 5000; i++) {
        backoff.nextDelay();
      }
      expect(backoff.nextDelay(), const Duration(seconds: 60));
    });

    test('custom parameters', () {
      final backoff = RetryBackoff(
        initialDelay: const Duration(milliseconds: 500),
        maxDelay: const Duration(seconds: 3),
        multiplier: 3,
      );
      expect(List.generate(4, (_) => backoff.nextDelay().inMilliseconds), [
        500,
        1500,
        3000,
        3000,
      ]);
    });
  });
}
