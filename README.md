# game_ads_manager

AdMob **mediation with real-time bidding** for Flutter games (Android + iOS), in a few lines of code.

One package gives your game:

- **Consent**: the Google UMP GDPR form, then the iOS App Tracking Transparency prompt, then the SDK start, always in that order.
- **7 bidding networks**: AdMob plus Unity Ads, ironSource, Meta Audience Network, AppLovin, Mintegral, Pangle and Liftoff Monetize (Vungle).
- **Preloading**: one interstitial and one rewarded ad are always ready. Failed loads retry with exponential backoff, and expired ads are replaced.
- **Rewarded ads** that return `true` only when the reward was earned, plus a notifier for your "Watch video" buttons.
- **Interstitial frequency cap**: minimum interval, every N calls, startup grace, and a cooldown after rewarded ads.
- **Widgets**: an adaptive banner widget and a native ad widget (Google templates, so no Kotlin/Swift needed).
- **Optional formats**: app open ads and rewarded interstitials.
- **Pause/resume callbacks** for your music and gameplay.
- **Remove-ads support** for an in-app purchase (rewarded ads stay available).
- **Revenue callback** with impression-level revenue, ready to send to Firebase Analytics.
- **Safety**: the package **never crashes your game**. Every ad error is caught, logged with a `[GameAds]` prefix, and the game continues.

> Versions used in 1.0.0 (checked on pub.dev, November 2026): `google_mobile_ads 9.2.0`,
> `gma_mediation_unity 1.12.0`, `gma_mediation_ironsource 2.7.1`, `gma_mediation_meta 1.7.1`,
> `gma_mediation_applovin 2.6.5`, `gma_mediation_mintegral 2.1.5`, `gma_mediation_pangle 4.2.1`,
> `gma_mediation_liftoffmonetize 1.5.6`, `app_tracking_transparency 2.0.7`.
> Requires **Flutter ≥ 3.38.1**, **Android minSdk 24**, **iOS 15.0**.

---

## Table of contents

1. [Add the package to a game](#1-add-the-package-to-a-game)
2. [Minimal usage (`main.dart`)](#2-minimal-usage)
3. [Native setup in the HOST GAME (Android + iOS)](#3-native-setup-in-the-host-game)
4. [AdMob dashboard: mediation groups with bidding](#4-admob-dashboard-mediation-with-bidding)
5. [app-ads.txt](#5-app-adstxt)
6. [Testing with Ad Inspector before release](#6-testing-before-release)
7. [Best practices for casual games](#7-best-practices-for-casual-games)
8. [Kids / family games](#8-kids--family-games)
9. [API reference](#9-api-reference)
10. [How it works / FAQ](#10-how-it-works--faq)

---

## 1. Add the package to a game

The package is hosted on GitHub, not pub.dev. In your **game's** `pubspec.yaml`:

```yaml
dependencies:
  game_ads_manager:
    git:
      url: https://github.com/9asso/game_ads_manager.git
      ref: v1.0.0          # a git tag, so every game gets exactly this version
```

Then run:

```bash
flutter pub get
```

**Updating to a new version:** create a new tag in this repo (e.g. `v1.1.0`), change `ref:` in the game, then run `flutter pub upgrade game_ads_manager`.

> Always use a **tag** for `ref`, never `main`. With `main`, every `flutter pub upgrade` could silently pull untested code into a game.

### If the repository is private

`flutter pub get` uses your normal `git`, so `git` must be able to clone the repo.

**Option A — SSH (recommended on your own computer)**

1. Create an SSH key if you don't have one: `ssh-keygen -t ed25519 -C "you@example.com"`.
2. Add `~/.ssh/id_ed25519.pub` in GitHub → Settings → SSH and GPG keys.
3. Check it works: `ssh -T git@github.com`.
4. Use the SSH URL:

```yaml
  game_ads_manager:
    git:
      url: git@github.com:9asso/game_ads_manager.git
      ref: v1.0.0
```

**Option B — HTTPS with your saved GitHub login.** Keep the `https://` URL and let git remember your credentials, e.g. with `gh auth login` (GitHub CLI) or the macOS keychain. The first `git clone` asks once.

**On CI (e.g. Codemagic, GitHub Actions):** add a read-only **deploy key** (SSH) to the repo, and give its private key to the CI.

> Never put a token in `pubspec.yaml` (`https://TOKEN@github.com/...`): it would be committed with your game's code.

---

## 2. Minimal usage

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:game_ads_manager/game_ads_manager.dart';

const adsConfig = AdsConfig(
  android: PlatformAdUnits(
    interstitial: 'ca-app-pub-1234567890123456/1111111111',
    rewarded:     'ca-app-pub-1234567890123456/2222222222',
    banner:       'ca-app-pub-1234567890123456/3333333333',
    native:       'ca-app-pub-1234567890123456/4444444444',
  ),
  ios: PlatformAdUnits(
    interstitial: 'ca-app-pub-1234567890123456/5555555555',
    rewarded:     'ca-app-pub-1234567890123456/6666666666',
    banner:       'ca-app-pub-1234567890123456/7777777777',
    native:       'ca-app-pub-1234567890123456/8888888888',
  ),
  // testMode: null (default) → Google TEST ads in debug builds, real ads in release.
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final ads = AdsManager.instance
    ..onFullScreenAdShow = () => MyAudio.pause()      // your music/gameplay
    ..onFullScreenAdDismiss = () => MyAudio.resume()
    ..onPaidEvent = (e) { /* later: FirebaseAnalytics.logAdImpression(...) */ };

  // If the player bought "Remove ads" (from your IAP/save data):
  // ads.setAdsRemoved(true);

  runApp(const MyGame());

  // Start AFTER runApp so the consent form / ATT prompt appear over your UI
  // and the first frame is not blocked.
  unawaited(ads.initialize(adsConfig));
}
```

Then use it anywhere in your game:

```dart
// Level completed → maybe an interstitial (the frequency rules decide).
await AdsManager.instance.showInterstitial(placement: 'level_complete');
goToNextLevel();

// "Watch a video to continue" button that enables itself when an ad is ready:
ValueListenableBuilder<bool>(
  valueListenable: AdsManager.instance.rewardedReadyNotifier,
  builder: (context, ready, _) => ElevatedButton(
    onPressed: ready
        ? () async {
            final earned = await AdsManager.instance.showRewarded(placement: 'continue');
            if (earned) revivePlayer();
          }
        : null,
    child: const Text('Watch video to continue'),
  ),
);

// Banner at the bottom of a MENU screen (not during gameplay):
Scaffold(
  body: ...,
  bottomNavigationBar: const SafeArea(child: AdsBanner()),
);

// Native ad on a level-complete / game-over screen:
const AdsNative(size: AdsNativeSize.medium); // or AdsNativeSize.small

// Settings menu (GDPR requires this button for EEA/UK users):
if (AdsManager.instance.isPrivacyOptionsRequired)
  TextButton(
    onPressed: AdsManager.instance.showPrivacyOptionsForm,
    child: const Text('Privacy settings'),
  ),
```

A complete demo is in [`example/lib/main.dart`](example/lib/main.dart).

---

## 3. Native setup in the HOST GAME

These steps are done **once per game**, in the game's `android/` and `ios/` folders. The package cannot do them for you. A fully configured reference is in [`example/android`](example/android) and [`example/ios`](example/ios).

> You do **not** need to register any plugin manually. Flutter automatically registers every plugin this package depends on: google_mobile_ads, the 7 adapters and ATT.

### 3.1 Android

#### a) AdMob App ID — `android/app/src/main/AndroidManifest.xml`

Find it in AdMob → Apps → (your app) → App settings → **App ID**. It contains a `~`, unlike ad unit IDs, which contain a `/`.

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application ...>
        <!-- AdMob App ID (yours!) -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-1234567890123456~1234567890"/>
        ...
    </application>
</manifest>
```

> Without this the app **crashes at launch**. For quick tests you can use Google's sample App ID: `ca-app-pub-3940256099942544~3347511713`.

#### b) Maven repositories (Mintegral, Pangle, ironSource)

The Mintegral and Pangle native SDKs are **not on Maven Central**, so Gradle must be told where they live. Google's ironSource guide also lists ironSource's repository, so we add it too.

**Kotlin DSL — `android/build.gradle.kts`** (the default for new Flutter projects):

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://android-sdk.is.com/") } // ironSource
        maven { url = uri("https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea") } // Mintegral
        maven { url = uri("https://artifact.bytedance.com/repository/pangle/") } // Pangle
    }
}
```

**Groovy — `android/build.gradle`** (older projects):

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url 'https://android-sdk.is.com/' }
        maven { url 'https://dl-maven-android.mintegral.com/repository/mbridge_android_sdk_oversea' }
        maven { url 'https://artifact.bytedance.com/repository/pangle/' }
    }
}
```

> If your project declares repositories in `android/settings.gradle(.kts)` inside
> `dependencyResolutionManagement { repositories { ... } }`, add the three `maven` lines **there** instead.

Symptom if you forget: `Could not find com.mbridge.msdk.oversea:...` or `Could not find com.pangle...` during the build.

#### c) minSdk 24 — `android/app/build.gradle.kts`

```kotlin
android {
    defaultConfig {
        minSdk = 24   // google_mobile_ads 9.x and all adapters require 24+
    }
}
```

(Groovy: `minSdkVersion 24`.)

#### d) Nothing else

The `AD_ID` and `INTERNET` permissions are added automatically by the Google Mobile Ads SDK (manifest merge). Kids games: see [section 8](#8-kids--family-games).

### 3.2 iOS

#### a) Minimum iOS version: 15.0

Meta Audience Network requires iOS 15.0. All other networks need 13.0.

- Xcode → Runner target → General → **Minimum Deployments** → iOS 15.0
  (new Flutter projects already use 15.0).
- Only if your project uses CocoaPods (it has an `ios/Podfile`): set the first line to `platform :ios, '15.0'`.

#### b) `ios/Runner/Info.plist`

Add inside the top-level `<dict>`:

```xml
<!-- AdMob App ID (yours!). AdMob → Apps → App settings → App ID. -->
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-1234567890123456~0987654321</string>

<!-- Text of the iOS tracking (ATT) prompt. REQUIRED, or the app crashes when ATT is requested. -->
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads to you.</string>
```

Google's sample iOS App ID for quick tests: `ca-app-pub-3940256099942544~1458002511`.

#### c) SKAdNetworkItems (Google + all 7 networks)

SKAdNetwork IDs let ad networks measure installs on iOS. A network (or one of its buyers) **can't bid properly** if its ID is missing, so you earn less.

The full list is in **[`doc/SKAdNetworkItems.xml`](doc/SKAdNetworkItems.xml)**: 157 unique IDs, ready to paste into `Info.plist` inside the top-level `<dict>`. The same list is already in [`example/ios/Runner/Info.plist`](example/ios/Runner/Info.plist).

It was built on 2026-11-06 by merging these official lists (refresh it about twice a year):

| Network | Official source |
|---|---|
| Google AdMob (+ Google's 3rd-party buyers) | https://developers.google.com/admob/ios/3p-skadnetworks |
| Unity Ads | https://skan.mz.unity3d.com/v3/partner/skadnetworks.plist.json |
| AppLovin | https://skadnetwork-ids.applovin.com/v1/skadnetworkids.json |
| Mintegral | https://dev.mintegral.com/skadnetworkids.json |
| Liftoff Monetize (Vungle) | https://vungle.com/skadnetworkids.xml |
| Meta Audience Network | https://developers.facebook.com/documentation/audience-network/setting-up/platform-setup/ios/SKAdNetwork (`v9wttpbfk9`, `n38lu8286q`) |
| ironSource | `su67r6k2v3` (included; full list: Unity LevelPlay "SKAdNetwork ID manager" in the LevelPlay docs) |
| Pangle | `22mmun2rn5` (global) and `238da6jt44` (China) (both included) |

<details>
<summary><b>Click to show the full SKAdNetworkItems block (157 IDs)</b></summary>

```xml
<key>SKAdNetworkItems</key>
<array>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cstr6suwn9.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>22mmun2rn5.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>238da6jt44.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>24t9a8vw3c.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>24zw6aqk47.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>252b5q8x7y.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>275upjj5gd.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>294l99pt4k.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>2fnua5tdw4.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>2u9pt9hc89.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>32z4fx6l9h.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>3l6bd9hu43.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>3qcr597p9d.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>3qy4746246.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>3rd42ekr43.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>3sh42y64q3.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>424m5254lk.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>4468km3ulz.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>44jx6755aq.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>44n7hlldy6.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>47vhws6wlr.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>488r3q3dtq.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>4dzt52r2t5.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>4fzdc2evr5.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>4mn522wn87.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>4pfyvq9l8r.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>4w7y6s5ca2.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>523jb4fst2.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>52fl2v3hgk.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>54nzkqm89y.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>578prtvx9j.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>5a6flpkh64.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>5f5u5tfb26.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>5l3tpt7t6e.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>5lm9lj6jb7.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>5tjdwbrq8w.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>6964rsfnh4.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>6g9af3uyq4.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>6p4ks3rnbw.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>6v7lgmsu45.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>6xzpu9s2p8.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>6yxyv74ff7.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>737z793b9f.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>74b6s63p6l.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>77y3x8wds4.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>7953jerfzd.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>79pbpufp6p.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>7fmhfwg9en.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>7rz58n8ntl.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>7ug5zh24hu.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>84993kbrcf.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>89z7zv988g.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>8c4e2ghe7u.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>8m87ys6875.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>8r8llnkz5a.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>8s468mfl3y.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>97r2b46745.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>9b89h5y424.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>9nlqeag3gk.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>9rd848q2bz.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>9t245vhmpl.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>9vvzujtq5s.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>9yg77x724h.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>a2p9lx4jpn.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>a7xqa6mtl2.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>a8cz6cu7e5.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>av6w8kgt66.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>b9bk5wbcq9.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>bxvub5ada5.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>c3frkrj4fj.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>c6k4g5qg8m.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cg4yq2srnc.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cj5566h2ga.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cp8zw746q7.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cs644xg564.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>dbu4b84rxf.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>dkc879ngq3.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>dzg6xy7pwj.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>e5fvkxwrpn.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>ecpz2srf59.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>eh6m2bh4zr.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>ejvt5qm6ak.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>f38h382jlk.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>f73kdq92p3.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>f7s53z58qe.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>feyaarzu9v.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>g28c52eehv.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>g2y4y55b64.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>g6gcrrvk4p.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>ggvn48r87g.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>glqzh8vgby.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>gta8lk7p23.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>gta9lk7p23.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>hb56zgv37p.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>hdw39hrw9y.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>hs6bdukanm.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>k674qkevps.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>k6y4y55b64.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>kbd757ywx3.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>kbmxgpxpgc.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>klf5c3l5u5.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>krvm3zuq6h.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>lr83yxwka7.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>ludvb6z3bs.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>m297p6643m.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>m5mvw97r93.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>m8dbw4sv7c.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>mj797d8u6f.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>mlmmfzh3r3.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>mls7yz5dvl.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>mp6xlyr22a.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>mqn7fxpca7.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>mtkv5xtk9e.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>n38lu8286q.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>n66cz3y3bx.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>n6fk4nfna4.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>n9x2a789qt.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>nzq8sh4pbs.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>p78axxw29g.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>ppxm28t8ap.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>prcb7njmu6.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>pwa73g5rt2.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>pwdxu55a5a.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>qqp299437r.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>qu637u8glc.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>r45fhb6rf7.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>rvh3l7un93.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>rx5hdcabgc.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>s39g8k73mm.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>s69wq72ugq.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>su67r6k2v3.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>t38b2kh725.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>tl55sbb4fm.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>u679fj5vs4.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>uw77j35x4d.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>v4nxqhlyqp.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>v72qych5uu.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>v79kvwwj4g.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>v9wttpbfk9.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>vcra2ehyfk.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>vhf287vqwu.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>vutu7akeur.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>w9q455wk68.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>wg4vff78zm.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>wzmmz9fp6w.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>x44k69ngh6.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>x5l83yy675.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>x8jxxk4ff5.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>x8uqf25wch.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>xga6mpmplv.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>xy9t38ct57.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>y45688jllp.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>y5ghdn5j9k.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>yclnxrl5pm.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>ydx93a7ass.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>zmvfpc5aq8.skadnetwork</string>
  </dict>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>zq492l623r.skadnetwork</string>
  </dict>
</array>
```

</details>

#### d) Native iOS dependencies (Swift Package Manager or CocoaPods)

google_mobile_ads, all 7 adapters and ATT support **Swift Package Manager**, which recent Flutter versions use by default. In that case there is **nothing to run**: `flutter build ios` / `flutter run` downloads everything. Verified with Flutter 3.47 and Xcode 26.

Older projects that still use **CocoaPods** (they have an `ios/Podfile`) must run:

```bash
cd ios
pod install --repo-update
cd ..
```

Run it again every time you change the `game_ads_manager` version. Open `ios/Runner.xcworkspace`, not `.xcodeproj`, in Xcode.

> The first iOS build downloads the ad SDKs (about 1 GB). Make sure you have disk space.

> The Meta SDK usually requires the latest Xcode. If the iOS build fails inside `FBAudienceNetwork`, update Xcode first.

---

## 4. AdMob dashboard: mediation with bidding

How it works: when your game asks for an ad, **AdMob runs a real-time auction** between AdMob and every network you added as a **bidding** source. The highest bid wins. No waterfall to configure.

### Step 0 — Create the accounts and the apps in each network

For each network, create your game's app in its own dashboard. Write down the IDs that AdMob will ask for:

| Network | Typical IDs AdMob asks for (Google's per-network guide has the exact list) |
|---|---|
| Unity Ads | Game ID, Placement ID per format |
| ironSource | App Key, Instance ID |
| Meta Audience Network | Placement ID per format (enable bidding with AdMob as the mediation partner in Meta Monetization Manager) |
| AppLovin | SDK Key (+ Ad Unit IDs) |
| Mintegral | App ID, App Key, Placement ID, Ad Unit ID |
| Pangle | App ID, Placement ID |
| Liftoff Monetize | App ID, Placement Reference ID |

Google's step-by-step guide for each network, including screenshots of what to copy:
`https://developers.google.com/admob/flutter/mediation/unity` (replace `unity` with `ironsource`, `meta`, `applovin`, `mintegral`, `pangle`, `liftoff-monetize`).

### Step 1 — Create your ad units in AdMob

AdMob → Apps → your app → Ad units → Add ad unit. Create one per format you use (Rewarded, Interstitial, Banner, Native), for **each platform**. Those `ca-app-pub-.../...` IDs go into `AdsConfig`.

### Step 2 — Create a mediation group per format AND per platform

AdMob → **Mediation** → **Create mediation group**:

1. **Ad format**: e.g. Rewarded. **Platform**: Android.
2. Name: e.g. `MusicGame – Rewarded – Android`.
3. **Ad units** → Add ad units → select your game's Android rewarded ad unit.
4. **Bidding** section → **Add ad source** → choose a network (e.g. *Unity Ads*) → enter the IDs from Step 0 (AdMob calls this "ad unit mapping").
5. Repeat step 4 for every network: Unity Ads, ironSource, Meta, AppLovin, Mintegral, Pangle, Liftoff Monetize.
   AdMob only lists the networks that support the selected format. Not every network serves native or banner.
6. Leave the **Waterfall** section with just AdMob Network (empty otherwise). You're using bidding only.
7. Save.

Repeat for every combination you use, e.g. 4 formats × 2 platforms = **8 mediation groups**:

```
Rewarded–Android   Interstitial–Android   Banner–Android   Native–Android
Rewarded–iOS       Interstitial–iOS       Banner–iOS       Native–iOS
```

### Step 3 — Privacy & messaging (GDPR) — mandatory for EEA/UK

AdMob → **Privacy & messaging**:

1. **GDPR** → Create message → select your apps → publish. This is the form the package shows through UMP.
2. In the GDPR message settings → **Ad partners** → make sure **all 7 networks** are in the list (Unity, ironSource, Meta, AppLovin, Mintegral, Pangle, Liftoff). A network that's not in the list does not get consent, and earns less or nothing in Europe.
3. Optional: **US state regulations** message (CCPA etc.), and add the same networks to its partner list.
4. Optional (iOS): **IDFA explainer** message. It explains tracking before the ATT prompt. The package then skips its own ATT request because the prompt has already been answered.

> **How consent reaches the networks.** Each adapter reads the GDPR consent automatically from the UMP form (IAB TCF / Google Additional Consent). The package deliberately does **not** call `setGDPRConsent(true)`-style methods: sending "true" for a user who said no would break the law.
> For US laws, set `AdsConfig.usPrivacyOptOut`. It's forwarded to ironSource, AppLovin, Unity and Liftoff before the SDK starts.

### Step 4 — Wait

New mediation groups and new network accounts can take **up to a few days** to fill and to show stable eCPMs. Don't judge a network on its first day.

---

## 5. app-ads.txt

**What it is.** A public text file listing every company that's allowed to sell ads in your apps. Buyers check it to avoid fraud. **Without it, many bidders refuse to bid on your inventory and your revenue drops.**

**Where it must be hosted.** At the **root of the developer website** listed on your store pages:

- Google Play Console → Store presence → Store settings → **Website**
- App Store Connect → App information → **Marketing URL** / your developer website

If your website is `https://9asso.com`, the file must be reachable at exactly `https://9asso.com/app-ads.txt`: root domain, plain text, HTTP 200. One file covers **all your games**.

Free hosting option: GitHub Pages on a custom domain. Put `app-ads.txt` at the repo root.

**Template** (one line per seller account, `#` = comment):

```text
# ============ Google AdMob ============
# AdMob → Apps → View all apps → "app-ads.txt" tab: copy YOUR line exactly.
# It looks like this (pub-ID = your publisher ID, last field = Google's certification ID):
google.com, pub-0000000000000000, DIRECT, f08c47fec0942fa0

# ============ Unity Ads ============
# Unity Cloud dashboard → Monetization → Settings / app-ads.txt: copy all lines shown.

# ============ ironSource (Unity LevelPlay) ============
# ironSource/LevelPlay dashboard → Account/Settings → app-ads.txt: copy all lines shown.

# ============ Meta Audience Network ============
# Meta Monetization Manager → Integration / app-ads.txt section: copy the line(s) with your ID.

# ============ AppLovin ============
# AppLovin dashboard → Account → app-ads.txt: copy all lines shown (AppLovin's list is long).

# ============ Mintegral ============
# Mintegral dashboard → App Setting / app-ads.txt: copy all lines shown.

# ============ Pangle ============
# Pangle dashboard → Apps → app-ads.txt: copy all lines shown.

# ============ Liftoff Monetize (Vungle) ============
# Liftoff Monetize dashboard → Settings / app-ads.txt: copy all lines shown.
```

> Don't guess these lines. Each network gives you lines containing **your own account ID**. Copy them exactly, including `DIRECT` / `RESELLER`. After publishing, AdMob checks the file within about 24h (AdMob → Apps → app-ads.txt status).

---

## 6. Testing before release

### Test ads (always safe)

- In **debug builds** (`flutter run`), `testMode: null` automatically uses **Google's test ad units**. Clicking them is safe.
- Test ad units **only show AdMob demo ads**. They do NOT test the other networks.

### Testing mediation (the real networks) with Ad Inspector

**Never click your own real ads.** Accounts get banned for that. Use a **test device**:

1. Run the game on your phone with `flutter run`.
2. Find your device's test ID in the log after the first ad request:
   - Android: `Use RequestConfiguration.Builder().setTestDeviceIds(Arrays.asList("33BE2250B43518CCDA7DE426D04EE231"))`
   - iOS: `GADMobileAds.sharedInstance.requestConfiguration.testDeviceIdentifiers = @[ @"2077ef9a63d2b398840261c8221a0c9b" ]`
3. Put it in the config, and force real ad units:

   ```dart
   AdsConfig(
     testMode: false,                       // real ad units, even in debug
     testDeviceIds: ['33BE2250B43518CCDA7DE426D04EE231'],
     ...
   )
   ```

   Real ad units on a registered test device return **test-labelled ads from the real auction**, which is safe.
4. Add a hidden debug button in your game that calls `AdsManager.instance.openAdInspector()`. You can also register the device under AdMob → Settings → Test devices and use the shake gesture.
5. In **Ad Inspector**:
   - **Ad units** → each mediation group → check every network's adapter shows "Initialized" (green).
   - **Ad source testing** → pick one network (e.g. Mintegral) → load a rewarded ad and check that network actually fills.
   - Common red errors: missing App ID / SDK key in the mediation group, missing Maven repo (Android), missing SKAdNetwork IDs (iOS), or the network's app not yet approved.
6. Watch the logs. With logging on, the package prints for example:

   ```
   [GameAds] adapter GADMediationAdapterUnity: ready
   [GameAds] rewarded: loaded (source: Mintegral)
   [GameAds] interstitial [level_end] skipped: min interval (12s < 60s)
   ```

### Testing the GDPR form outside Europe

Set `debugConsentAsEea: true` with your device in `testDeviceIds`. This only works in debug/profile builds. Uninstall the app to see the form again, because consent is stored on the device.

### Release checklist

- [ ] `testMode` is `null` or `false` in the release build, and the real ad unit IDs are in `AdsConfig`
- [ ] Your own AdMob **App ID** in `AndroidManifest.xml` and `Info.plist` (not the sample `3940256099942544` one)
- [ ] `testDeviceIds` contains only your own devices (it's harmless to leave them)
- [ ] GDPR message published, all networks in its ad partner list
- [ ] app-ads.txt live on your developer website
- [ ] Every mediation group has all bidding sources, checked in Ad Inspector
- [ ] Privacy settings button in your settings menu (`isPrivacyOptionsRequired`)

---

## 7. Best practices for casual games

**Rewarded ads (your best earner, players like them):**
- Offer them where the player *wants* something: continue after losing, double coins after a level, unlock a song/level early, a free daily reward.
- Show the button **only when an ad is ready** (`rewardedReadyNotifier`). A greyed-out "Loading…" is fine; a button that does nothing is not.
- Always give the reward exactly as promised, but only when `showRewarded()` returns `true`.
- Rewarded ads stay available after "Remove ads". Players choose them, and they keep earning.

**Interstitials (useful but annoying if overused):**
- Show them **only at natural breaks**: level complete, game over, back to menu. **Never during gameplay** and never on a button the player taps in a hurry.
- Start with the defaults (60s apart, every 2nd level, not in the first 30s, not within 30s after a rewarded ad), then tune with retention data.
- Use `placement:` names (`'level_complete'`, `'game_over'`) so revenue can be analysed per placement.
- In a rhythm/music game: **never** right before a song starts. Show the ad after the score screen.

**Banners and native ads:**
- Only on menus, song lists, results screens. **Never over the gameplay area**, which causes accidental taps and policy strikes.
- Leave space so the banner never covers buttons. `AdsBanner` takes no space until loaded, so design your layout to handle both cases.

**Audio:** always pause music and gameplay in `onFullScreenAdShow` and resume in `onFullScreenAdDismiss`. Otherwise you get two audio tracks at once, and in rhythm games the player loses a run.

**Remove ads IAP:** call `setAdsRemoved(true)` at every startup when the purchase is owned. The package doesn't store it; your purchase/restore logic is the source of truth.

---

## 8. Kids / family games

If a game targets children (Google Play "Designed for Families" / Teacher Approved, Apple Kids category, or COPPA):

1. **In the AdMob mediation groups for that game, simply do not add Meta Audience Network**, or any other network that is not certified for families. Only add networks listed in Google Play's **Families Self-Certified Ads SDK** list (check the current list in Play Console Help; it changes).
   You don't need a different version of this package. Networks that are not in the mediation group never receive a request.
2. Also note: **AppLovin and Pangle do not serve child-directed users at all** (their adapters return "user is a child" errors). Unity Ads requires the "Mixed audience" setting in its dashboard. So for kids games, leave AppLovin and Pangle out of the mediation group too.
3. Configure the package:

   ```dart
   AdsConfig(
     tagForChildDirectedTreatment: true,
     tagForUnderAgeOfConsent: true,
     maxAdContentRating: AdContentRating.g,
     ...
   )
   ```

4. Android: remove the advertising ID permission in `AndroidManifest.xml` (required by Play for apps that target only children):

   ```xml
   <manifest xmlns:android="http://schemas.android.com/apk/res/android"
             xmlns:tools="http://schemas.android.com/tools">
       <uses-permission android:name="com.google.android.gms.permission.AD_ID" tools:node="remove"/>
   ```

5. iOS: apps in the Kids category must not use ATT or tracking. Don't add `NSUserTrackingUsageDescription`, and don't ship such a game with the ATT prompt. For a kids-only iOS game, ask for a variant of this package without ATT.

---

## 9. API reference

```dart
// Setup
Future<void> AdsManager.instance.initialize(AdsConfig config); // never throws; 2nd call returns the 1st future
bool get isInitialized;
bool get canRequestAds;

// Rewarded (available even when ads are removed)
bool get isRewardedReady;
ValueListenable<bool> get rewardedReadyNotifier;
Future<bool> showRewarded({String? placement});                 // true only if earned
bool get isRewardedInterstitialReady;
ValueListenable<bool> get rewardedInterstitialReadyNotifier;
Future<bool> showRewardedInterstitial({String? placement});

// Interstitial (frequency-capped)
Future<void> showInterstitial({String? placement});             // completes after the ad closes

// Callbacks
VoidCallback? onFullScreenAdShow;
VoidCallback? onFullScreenAdDismiss;
void Function(AdPaidEvent event)? onPaidEvent;

// Remove ads
void setAdsRemoved(bool removed);
bool get adsRemoved;

// Privacy & debug
bool get isPrivacyOptionsRequired;
Future<void> showPrivacyOptionsForm();
Future<void> openAdInspector();

// Widgets
const AdsBanner();
const AdsNative({AdsNativeSize size = AdsNativeSize.medium, Color? backgroundColor,
                 Color? textColor, Color? buttonColor, Color? buttonTextColor,
                 double cornerRadius = 12});
```

### `AdsConfig`

| Field | Default | Meaning |
|---|---|---|
| `android`, `ios` | empty | `PlatformAdUnits(banner, interstitial, rewarded, rewardedInterstitial, appOpen, native)`; `null` = format disabled |
| `testMode` | `null` | `null`: test ads in debug, real ads in release · `true`: always test · `false`: always real (for Ad Inspector) |
| `testDeviceIds` | `[]` | your test devices |
| `tagForChildDirectedTreatment` | `null` | COPPA child-directed |
| `tagForUnderAgeOfConsent` | `null` | GDPR under age of consent |
| `maxAdContentRating` | `null` | `AdContentRating.g / pg / t / ma` |
| `interstitialRules` | 60s / every 2 / 30s / 30s | `InterstitialRules(minSecondsBetween, showEveryNCalls, startupGraceSeconds, cooldownAfterRewardedSeconds)` |
| `appOpenCooldown` | 4 h | minimum time between app open ads |
| `attPromptDelay` | 1 s | delay before the iOS ATT prompt |
| `usPrivacyOptOut` | `null` | US "do not sell" choice forwarded to ironSource, AppLovin, Unity, Liftoff |
| `debugConsentAsEea` | `false` | show the GDPR form outside Europe (test devices, non-release) |
| `enableLogging` | `true` | `[GameAds]` logs |

### `AdPaidEvent` → Firebase (later)

```dart
AdsManager.instance.onPaidEvent = (e) {
  FirebaseAnalytics.instance.logAdImpression(
    adPlatform: 'admob',
    adFormat: e.format.name,
    adUnitName: e.adUnitId,
    value: e.value,              // valueMicros / 1,000,000
    currency: e.currencyCode,
  );
};
```

Fields: `format`, `adUnitId`, `valueMicros`, `currencyCode`, `precision` (`unknown / estimated / publisherProvided / precise`), `placement`, `value`.

---

## 10. How it works / FAQ

**Startup order (`initialize`)**
1. UMP: `requestConsentInfoUpdate`, then `loadAndShowConsentFormIfRequired`. If the device is offline, the consent saved in a previous session is used.
2. iOS: wait `attPromptDelay`, then request ATT if it was never answered.
3. If `canRequestAds()`: forward the US privacy choice, apply `RequestConfiguration` (test devices, child tags, rating), call `MobileAds.initialize()` (logs each adapter's state; gives up waiting after 15s, but ads still load), then preload.
4. If consent doesn't allow ads, nothing loads, and the game runs normally without ads. If the user later changes their choice via `showPrivacyOptionsForm()`, ads start.

**Preloading:** one rewarded and one interstitial (and an app open ad, if enabled) are kept loaded. After each show or failure the next one loads. Failed loads retry after 2s, 4s, 8s, 16s, 32s, then every 60s. Cached ads older than 55 minutes are discarded and reloaded, because ads expire after about an hour.

**Frequency cap:** every `showInterstitial()` call counts as one opportunity. An ad is shown when at least `showEveryNCalls` opportunities happened since the last interstitial **and** all time rules pass. If the ad wasn't loaded yet, the counter is kept, so the next opportunity shows it.

**App open ads** (optional, off unless you set `appOpen` IDs) are shown only when the app returns from the background. Never on a cold start, never during the first session after install, never while or within 30s after another full-screen ad, and at most once per `appOpenCooldown`.

**Rewarded result:** `showRewarded()` completes when the ad closes. It waits up to 0.6s more for networks that report the reward slightly after closing. If no ad is ready, it returns `false` immediately.

**Why does `showInterstitial()` do nothing?** Look at the `[GameAds]` log. It always says why (`startup grace`, `min interval`, `call 1 of 2`, `not loaded yet`, `ads removed`…).

**Web/desktop?** All methods are safe no-ops there.

---

## License

MIT, see [LICENSE](LICENSE).
