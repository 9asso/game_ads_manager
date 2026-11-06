import 'package:flutter_test/flutter_test.dart';
import 'package:game_ads_manager/game_ads_manager.dart';
import 'package:game_ads_manager/src/logic/interstitial_frequency_cap.dart';

/// A clock the test moves forward manually.
class FakeClock {
  DateTime now = DateTime(2026, 1, 1, 12);

  DateTime call() => now;

  void advance(int seconds) => now = now.add(Duration(seconds: seconds));
}

void main() {
  late FakeClock clock;

  InterstitialFrequencyCap cap([
    InterstitialRules rules = const InterstitialRules(),
  ]) => InterstitialFrequencyCap(rules: rules, clock: clock.call);

  setUp(() => clock = FakeClock());

  group('InterstitialFrequencyCap (defaults: 60s / every 2 / 30s / 30s)', () {
    test('blocks during the startup grace period', () {
      final c = cap();
      c.evaluate();
      clock.advance(29);
      final d = c.evaluate();
      expect(d.allowed, isFalse);
      expect(d.reason, contains('startup'));
    });

    test('allows on the 2nd call once grace has passed', () {
      final c = cap();
      clock.advance(31);
      expect(c.evaluate().allowed, isFalse); // call 1 of 2
      expect(c.evaluate().allowed, isTrue); // call 2 of 2
    });

    test('calls during grace still count toward every-N', () {
      final c = cap();
      c.evaluate(); // blocked by grace, but counted
      clock.advance(31);
      expect(c.evaluate().allowed, isTrue);
    });

    test('enforces minimum seconds between interstitials', () {
      final c = cap();
      clock.advance(31);
      c.evaluate();
      expect(c.evaluate().allowed, isTrue);
      c.recordInterstitialShown();

      clock.advance(10);
      c.evaluate();
      final d = c.evaluate();
      expect(d.allowed, isFalse);
      expect(d.reason, contains('min interval'));

      clock.advance(50); // 60s since last
      expect(c.evaluate().allowed, isTrue);
    });

    test('recordInterstitialShown resets the call counter', () {
      final c = cap();
      clock.advance(31);
      c
        ..evaluate()
        ..evaluate()
        ..recordInterstitialShown();
      expect(c.callsSinceLastShow, 0);
      clock.advance(120);
      expect(c.evaluate().allowed, isFalse); // 1 of 2 again
      expect(c.evaluate().allowed, isTrue);
    });

    test('if the ad was not shown, the next call may show it', () {
      final c = cap();
      clock.advance(31);
      c.evaluate();
      expect(c.evaluate().allowed, isTrue);
      // Ad was not loaded -> recordInterstitialShown() NOT called.
      expect(c.evaluate().allowed, isTrue);
    });

    test('blocks shortly after a rewarded ad', () {
      final c = cap();
      clock.advance(100);
      c.evaluate();
      c.recordRewardedShown();
      clock.advance(10);
      final d = c.evaluate();
      expect(d.allowed, isFalse);
      expect(d.reason, contains('rewarded'));
      clock.advance(20); // 30s after rewarded
      expect(c.evaluate().allowed, isTrue);
    });

    test('check() does not count a call', () {
      final c = cap();
      clock.advance(31);
      c.check();
      c.check();
      expect(c.callsSinceLastShow, 0);
      expect(c.check().allowed, isFalse);
    });
  });

  group('custom rules', () {
    test('showEveryNCalls = 1 shows every time (subject to timing)', () {
      final c = cap(
        const InterstitialRules(
          showEveryNCalls: 1,
          startupGraceSeconds: 0,
          minSecondsBetween: 0,
        ),
      );
      expect(c.evaluate().allowed, isTrue);
      c.recordInterstitialShown();
      expect(c.evaluate().allowed, isTrue);
    });

    test('showEveryNCalls below 1 behaves like 1', () {
      final c = cap(
        const InterstitialRules(showEveryNCalls: 0, startupGraceSeconds: 0),
      );
      expect(c.evaluate().allowed, isTrue);
    });

    test('every 3 calls', () {
      final c = cap(
        const InterstitialRules(
          showEveryNCalls: 3,
          startupGraceSeconds: 0,
          minSecondsBetween: 0,
        ),
      );
      final results = <bool>[];
      for (var i = 0; i < 6; i++) {
        final allowed = c.evaluate().allowed;
        results.add(allowed);
        if (allowed) c.recordInterstitialShown();
      }
      expect(results, [false, false, true, false, false, true]);
    });
  });
}
