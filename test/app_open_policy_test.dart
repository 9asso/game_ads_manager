import 'package:flutter_test/flutter_test.dart';
import 'package:game_ads_manager/src/app_open/app_open_policy.dart';

void main() {
  late DateTime now;
  late AppOpenPolicy policy;

  setUp(() {
    now = DateTime(2026, 1, 1, 12);
    policy = AppOpenPolicy(
      cooldown: const Duration(hours: 4),
      clock: () => now,
    );
  });

  bool allowed({
    bool firstLaunch = false,
    bool removed = false,
    bool showing = false,
    DateTime? lastDismissed,
  }) => policy
      .check(
        isFirstLaunch: firstLaunch,
        adsRemoved: removed,
        fullScreenAdShowing: showing,
        lastFullScreenDismissedAt: lastDismissed,
      )
      .allowed;

  test('allowed in the normal case', () => expect(allowed(), isTrue));

  test('never on first launch', () {
    expect(allowed(firstLaunch: true), isFalse);
  });

  test('never when ads are removed', () {
    expect(allowed(removed: true), isFalse);
  });

  test('never while another full-screen ad is open', () {
    expect(allowed(showing: true), isFalse);
  });

  test('never right after another full-screen ad', () {
    final dismissed = now.subtract(const Duration(seconds: 5));
    expect(allowed(lastDismissed: dismissed), isFalse);
    now = now.add(const Duration(seconds: 30));
    expect(allowed(lastDismissed: dismissed), isTrue);
  });

  test('respects the cooldown', () {
    policy.recordShown();
    now = now.add(const Duration(hours: 3, minutes: 59));
    expect(allowed(), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(allowed(), isTrue);
  });
}
