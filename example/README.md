# game_ads_manager example

Demo app that uses **Google test ads only** (`testMode: true`).

```bash
cd example
flutter pub get
flutter run
```

Buttons: interstitial, rewarded (shows whether the reward was earned), native
ad, privacy settings (only when required in your region), Ad Inspector, and a
"remove ads" switch. A banner is anchored at the bottom.

The native setup a real game needs (App IDs, Maven repositories, minSdk 24,
iOS 15, SKAdNetwork IDs, ATT text) is already done here. Compare with
`android/build.gradle.kts`, `android/app/build.gradle.kts`,
`android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist`.
