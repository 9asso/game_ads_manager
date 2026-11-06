import 'dart:async';

import 'package:flutter/material.dart';
import 'package:game_ads_manager/game_ads_manager.dart';

/// Demo configuration. `testMode: true` forces Google's test ad units, so the
/// placeholder IDs below are never used.
const adsConfig = AdsConfig(
  testMode: true,
  android: PlatformAdUnits(
    banner: 'ca-app-pub-XXXXXXXXXXXXXXXX/1111111111',
    interstitial: 'ca-app-pub-XXXXXXXXXXXXXXXX/2222222222',
    rewarded: 'ca-app-pub-XXXXXXXXXXXXXXXX/3333333333',
    native: 'ca-app-pub-XXXXXXXXXXXXXXXX/4444444444',
  ),
  ios: PlatformAdUnits(
    banner: 'ca-app-pub-XXXXXXXXXXXXXXXX/5555555555',
    interstitial: 'ca-app-pub-XXXXXXXXXXXXXXXX/6666666666',
    rewarded: 'ca-app-pub-XXXXXXXXXXXXXXXX/7777777777',
    native: 'ca-app-pub-XXXXXXXXXXXXXXXX/8888888888',
  ),
  // Demo-friendly rules (use the defaults in a real game).
  interstitialRules: InterstitialRules(
    minSecondsBetween: 10,
    showEveryNCalls: 1,
    startupGraceSeconds: 0,
    cooldownAfterRewardedSeconds: 5,
  ),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DemoApp());
  // Don't block the first frame: consent form, ATT and SDK start run after.
  unawaited(AdsManager.instance.initialize(adsConfig));
}

/// The demo app.
class DemoApp extends StatelessWidget {
  /// Creates the demo app.
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'game_ads_manager demo',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const DemoHome(),
    );
  }
}

/// The single demo screen.
class DemoHome extends StatefulWidget {
  /// Creates the demo screen.
  const DemoHome({super.key});

  @override
  State<DemoHome> createState() => _DemoHomeState();
}

class _DemoHomeState extends State<DemoHome> {
  final ads = AdsManager.instance;
  String _status = 'Ready.';
  bool _musicPlaying = true;
  bool _showNative = false;

  @override
  void initState() {
    super.initState();
    // In a real game: pause / resume music and gameplay.
    ads.onFullScreenAdShow = () => setState(() => _musicPlaying = false);
    ads.onFullScreenAdDismiss = () => setState(() => _musicPlaying = true);
    // In a real game: send to Firebase Analytics (ad_impression).
    ads.onPaidEvent = (event) => debugPrint('Revenue: $event');
    // Same future as in main(): rebuild once consent is known so the
    // "Privacy settings" button appears if required.
    ads.initialize(adsConfig).then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _levelComplete() async {
    setState(() => _status = 'Level complete → showInterstitial()');
    await ads.showInterstitial(placement: 'level_complete');
    if (mounted) setState(() => _status = 'Next level!');
  }

  Future<void> _watchVideo() async {
    final earned = await ads.showRewarded(placement: 'double_coins');
    if (!mounted) return;
    setState(
      () => _status = earned
          ? '🎉 Reward earned: coins doubled!'
          : 'No reward (ad not ready or closed early).',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('game_ads_manager')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _musicPlaying ? '🎵 Music playing' : '⏸ Music paused (ad open)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(_status),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _levelComplete,
            child: const Text('Show interstitial (level complete)'),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<bool>(
            valueListenable: ads.rewardedReadyNotifier,
            builder: (context, ready, _) => FilledButton.icon(
              onPressed: ready ? _watchVideo : null,
              icon: const Icon(Icons.play_circle),
              label: Text(
                ready ? 'Watch video: double coins' : 'Loading video…',
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() => _showNative = !_showNative),
            child: Text(_showNative ? 'Hide native ad' : 'Show native ad'),
          ),
          if (_showNative) ...[
            const SizedBox(height: 12),
            const AdsNative(size: AdsNativeSize.medium),
          ],
          const Divider(height: 40),
          if (ads.isPrivacyOptionsRequired)
            OutlinedButton(
              onPressed: ads.showPrivacyOptionsForm,
              child: const Text('Privacy settings'),
            )
          else
            const Text(
              'Privacy settings button hidden (not required in your region).',
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: ads.openAdInspector,
            child: const Text('Open Ad Inspector'),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Remove ads (simulated purchase)'),
            subtitle: const Text('Rewarded stays available'),
            value: ads.adsRemoved,
            onChanged: (v) => setState(() => ads.setAdsRemoved(v)),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: AdsBanner()),
    );
  }
}
