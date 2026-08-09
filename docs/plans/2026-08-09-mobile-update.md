# Mobile App Update Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship mobile version `v1.0.0`, publish a website-hosted update policy, and let the Android website build securely download and hand an APK to the system installer while store builds remain store-only.

**Architecture:** A pure-Dart update core parses and evaluates a platform-specific JSON policy fetched from a fixed HTTPS URL. Riverpod coordinates automatic/manual checks and UI prompts. Android exposes a narrow MethodChannel for distribution-channel discovery, SHA-256 verification, unknown-source permission, and installer launch; only the `website` product flavor declares package-install permissions.

**Tech Stack:** Flutter/Dart, Riverpod, Dio, SharedPreferences, Android Kotlin/PackageInstaller intent, Gradle Kotlin DSL, Node `node:test` validation.

---

### Task 1: Establish the v1.0.0 version and website policy contract

**Files:**
- Create: `website/app-update.json`
- Create: `tests/website/mobileAppUpdateManifest.test.js`
- Modify: `app/pubspec.yaml:4`
- Modify: `app/lib/core/app_version.dart:1-2`
- Modify: `docs/BUILD-PACKAGING.md:79-116`

**Step 1: Write the failing website contract test**

Add a Node test that reads `website/app-update.json`, asserts `schemaVersion === 1`, asserts iOS/Android/Harmony version names are `1.0.0`, checks Android `latestBuild === 2002`, checks Harmony `latestBuild === 1000000`, and verifies Android `updateUrl` resolves to `website/downloads/ZT-Monitor-Android.apk`. Also assert `app/pubspec.yaml` contains `version: 1.0.0+2002` and `app_version.dart` displays `v1.0.0`.

**Step 2: Run the test and verify failure**

Run: `node --test tests/website/mobileAppUpdateManifest.test.js`

Expected: FAIL because `website/app-update.json` does not exist and the Flutter version is still alpha.

**Step 3: Add the initial policy and version constants**

Use this policy shape, leaving unavailable store URLs disabled rather than inventing IDs:

```json
{
  "schemaVersion": 1,
  "ios": {
    "enabled": false,
    "latestVersion": "1.0.0",
    "latestBuild": 2002,
    "minimumBuild": 2002,
    "delivery": "store",
    "updateUrl": "",
    "releaseNotes": "ZT助手移动端 v1.0.0 正式发布。"
  },
  "android": {
    "enabled": true,
    "latestVersion": "1.0.0",
    "latestBuild": 2002,
    "minimumBuild": 2002,
    "delivery": "direct",
    "updateUrl": "downloads/ZT-Monitor-Android.apk",
    "sha256": "",
    "releaseNotes": "ZT助手移动端 v1.0.0 正式发布。"
  },
  "ohos": {
    "enabled": false,
    "latestVersion": "1.0.0",
    "latestBuild": 1000000,
    "minimumBuild": 1000000,
    "delivery": "store",
    "updateUrl": "",
    "releaseNotes": "ZT助手移动端 v1.0.0 正式发布。"
  }
}
```

Set `app/pubspec.yaml` to `version: 1.0.0+2002`. Replace the display-only constant with:

```dart
const String kAppVersionName = '1.0.0';
const String kAppVersion = 'v$kAppVersionName';
const int kAppBuildNumber = 2002;
const int kOhosBuildNumber = 1000000;
```

Document the new Android flavor commands and version numbers.

**Step 4: Run the test and verify success**

Run: `node --test tests/website/mobileAppUpdateManifest.test.js`

Expected: PASS.

**Step 5: Commit**

```bash
git add website/app-update.json tests/website/mobileAppUpdateManifest.test.js app/pubspec.yaml app/lib/core/app_version.dart docs/BUILD-PACKAGING.md
git commit -m "feat(app): establish v1.0.0 update policy"
```

### Task 2: Build the pure-Dart policy parser and decision engine

**Files:**
- Create: `app/lib/core/update/app_update_policy.dart`
- Create: `app/test/core/app_update_policy_test.dart`

**Step 1: Write failing parser and decision tests**

Cover:

- valid direct/store policy parsing;
- unknown `schemaVersion`, missing fields, negative builds, non-HTTPS absolute URLs, and unsupported delivery rejection;
- relative Android APK URL resolution against the policy URL;
- `latestBuild <= currentBuild` => up to date;
- `currentBuild < minimumBuild` => required update;
- otherwise `latestBuild > currentBuild` => optional update;
- disabled platform => unavailable.

Use public model types:

```dart
enum AppUpdateDelivery { store, direct }
enum AppUpdateUrgency { none, optional, required }

final class PlatformUpdatePolicy {
  const PlatformUpdatePolicy({
    required this.enabled,
    required this.latestVersion,
    required this.latestBuild,
    required this.minimumBuild,
    required this.delivery,
    required this.updateUri,
    required this.sha256,
    required this.releaseNotes,
  });
}
```

**Step 2: Run the test and verify failure**

Run: `cd app && flutter test test/core/app_update_policy_test.dart`

Expected: FAIL because the update model does not exist.

**Step 3: Implement the minimal parser and evaluator**

Implement `AppUpdatePolicy.fromJson`, `policyFor(String operatingSystem)`, and `evaluateUpdate(currentBuild:)`. Resolve relative URLs with `policyUri.resolve(...)`; require HTTPS after resolution. Treat an empty URL as valid only when `enabled` is false.

**Step 4: Run the test and verify success**

Run: `cd app && flutter test test/core/app_update_policy_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/lib/core/update/app_update_policy.dart app/test/core/app_update_policy_test.dart
git commit -m "feat(app): parse mobile update policy"
```

### Task 3: Add check orchestration, throttling, and platform abstraction

**Files:**
- Create: `app/lib/core/update/app_update_platform.dart`
- Create: `app/lib/core/update/app_update_platform_io.dart`
- Create: `app/lib/core/update/app_update_platform_web.dart`
- Create: `app/lib/core/update/app_update_service.dart`
- Create: `app/test/core/app_update_service_test.dart`
- Modify: `app/lib/core/storage/prefs_storage.dart:15-28`

**Step 1: Write failing service tests**

Inject a fake HTTP fetcher, clock, platform descriptor, and preferences. Cover:

- the configured policy URL is fetched without Hub authorization;
- empty `ZT_UPDATE_POLICY_URL` returns a disabled/configuration result;
- automatic checks are suppressed for 12 hours after a successful attempt;
- manual checks bypass throttling;
- timeout/HTTP/parse errors become typed non-fatal results;
- Android uses build `2002`, Harmony uses `1000000`;
- web reports unsupported.

Persist the last successful automatic attempt under `app_update.last_check_at`.

**Step 2: Run the test and verify failure**

Run: `cd app && flutter test test/core/app_update_service_test.dart`

Expected: FAIL because the service does not exist.

**Step 3: Implement the service**

Use a dedicated unauthenticated Dio instance with a 10-second connect/receive timeout and `Accept: application/json`. Read the URL from:

```dart
const kUpdatePolicyUrl = String.fromEnvironment('ZT_UPDATE_POLICY_URL');
```

Do not reuse `dioProvider`, because it is scoped to the user-configurable Hub and injects Hub credentials. Use conditional imports so web builds compile without `dart:io`; the IO adapter maps `Platform.operatingSystem` to `ios`, `android`, or `ohos`.

**Step 4: Run the test and verify success**

Run: `cd app && flutter test test/core/app_update_service_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/lib/core/update app/test/core/app_update_service_test.dart app/lib/core/storage/prefs_storage.dart
git commit -m "feat(app): orchestrate update checks"
```

### Task 4: Add lifecycle checks and the About-page update UI

**Files:**
- Create: `app/lib/core/update/app_update_lifecycle.dart`
- Create: `app/lib/core/update/app_update_dialog.dart`
- Create: `app/test/app_update_ui_test.dart`
- Modify: `app/lib/app.dart:9-58`
- Modify: `app/lib/features/me/me_page.dart:89-110`

**Step 1: Write failing widget tests**

Override the update service/provider and cover:

- “我的 → 关于” contains “检查更新”;
- manual up-to-date result shows “已是最新版本”;
- optional update dialog has “稍后” and “立即更新”;
- required update dialog omits “稍后” and cannot be dismissed by tapping outside;
- automatic network failure produces no dialog;
- first post-frame check occurs once and resumed checks call the throttled automatic path.

**Step 2: Run the tests and verify failure**

Run: `cd app && flutter test test/app_update_ui_test.dart`

Expected: FAIL because the row and lifecycle bridge do not exist.

**Step 3: Implement the UI and lifecycle bridge**

Wrap the routed child with `AppUpdateLifecycle` inside `MaterialApp.router.builder`, next to the existing brightness lifecycle wrapper. Use a single-flight guard so a resumed event cannot stack dialogs. The manual row displays an in-progress state, calls the manual service path, and renders success/error feedback through the existing theme.

**Step 4: Run the tests and verify success**

Run: `cd app && flutter test test/app_update_ui_test.dart test/widget_test.dart test/theme_test.dart`

Expected: PASS.

**Step 5: Commit**

```bash
git add app/lib/core/update/app_update_lifecycle.dart app/lib/core/update/app_update_dialog.dart app/lib/app.dart app/lib/features/me/me_page.dart app/test/app_update_ui_test.dart
git commit -m "feat(app): surface mobile update checks"
```

### Task 5: Add Android website/store flavors and the secure installer bridge

**Files:**
- Create: `app/android/app/src/website/AndroidManifest.xml`
- Create: `app/android/app/src/main/res/xml/update_file_paths.xml`
- Create: `app/android/key.properties.example`
- Create: `app/lib/core/update/android_update_installer.dart`
- Create: `app/test/core/android_update_installer_test.dart`
- Modify: `app/android/app/build.gradle.kts:1-39`
- Modify: `app/android/app/src/main/kotlin/com/zneox/ztoken/ztoken_monitor/MainActivity.kt:1-5`
- Modify: `app/android/.gitignore`
- Modify: `docs/BUILD-PACKAGING.md:95-116`

**Step 1: Write the failing Dart bridge tests**

Mock `MethodChannel('com.zneox.ztoken_monitor/app_update')` and cover `website`, `store`, SHA mismatch, unknown-source permission required, installer opened, and unsupported platform results. Verify store builds never call the direct installer.

**Step 2: Run the test and verify failure**

Run: `cd app && flutter test test/core/android_update_installer_test.dart`

Expected: FAIL because the bridge does not exist.

**Step 3: Add distribution flavors and signing configuration**

Add Gradle flavor dimension `distribution` with `website` and `store`. Only `src/website/AndroidManifest.xml` declares `REQUEST_INSTALL_PACKAGES` and an AndroidX `FileProvider`. Load `android/key.properties` and configure Release signing; fail Release configuration with a clear message when the file is missing instead of falling back to Debug signing. Keep the same application ID for both flavors.

The committed example contains names only:

```properties
storeFile=/absolute/path/outside/repository/ztoken-monitor-release.jks
storePassword=CHANGE_ME
keyAlias=ztoken-monitor
keyPassword=CHANGE_ME
```

**Step 4: Implement the Kotlin channel**

Expose:

- `getDistribution`: return `BuildConfig.FLAVOR`;
- `verifyAndInstallApk(path, sha256)`: reject non-website builds, calculate SHA-256 using `MessageDigest`, request unknown-source settings when required, and launch `ACTION_VIEW` with a FileProvider URI and read permission;
- typed statuses: `permissionRequired`, `installerOpened`, and errors.

Restrict shared paths to the app cache directory. Never accept an arbitrary external file path.

**Step 5: Implement direct download orchestration**

Download with a dedicated Dio client to a deterministic file under `Directory.systemTemp`, delete a partial file on failure, then call the native bridge. Disable the action if policy SHA-256 is empty. Surface progress and actionable permission text in the update dialog.

**Step 6: Run tests and compile both flavors**

Run:

```bash
cd app
flutter test test/core/android_update_installer_test.dart
flutter build apk --debug --flavor website --dart-define=ZT_UPDATE_POLICY_URL=https://example.invalid/app-update.json
flutter build apk --debug --flavor store --dart-define=ZT_UPDATE_POLICY_URL=https://example.invalid/app-update.json
```

Expected: Dart tests PASS; both Debug APKs compile; `aapt dump permissions` shows `REQUEST_INSTALL_PACKAGES` only in the website APK.

**Step 7: Commit**

```bash
git add app/android app/lib/core/update/android_update_installer.dart app/test/core/android_update_installer_test.dart docs/BUILD-PACKAGING.md
git commit -m "feat(android): install signed website updates"
```

### Task 6: Produce and verify the signed website release artifact

**Files:**
- Local-only: `app/android/key.properties`
- Local/external secret: Android Release keystore
- Modify binary: `website/downloads/ZT-Monitor-Android.apk`
- Modify: `website/app-update.json`
- Modify: `website/downloads/README.md`

**Step 1: Configure the long-lived Release key**

Create or select a keystore outside Git, back it up securely, and populate ignored `app/android/key.properties`. Do not print passwords or put them in shell history, Git, plan files, or logs.

**Step 2: Build the formal website APK**

Run:

```bash
cd app
flutter build apk --release --flavor website --dart-define=ZT_UPDATE_POLICY_URL=https://<产品官网>/app-update.json
```

Expected: `build/app/outputs/flutter-apk/app-website-release.apk` exists and is Release-signed.

**Step 3: Verify before replacing the website binary**

Run `aapt dump badging` and `apksigner verify --print-certs`. Expected package `com.zneox.ztoken.ztoken_monitor`, version name `1.0.0`, version code `2002`, and a non-Debug certificate. Copy the verified artifact over `website/downloads/ZT-Monitor-Android.apk` only after these checks pass.

**Step 4: Publish the artifact hash into the policy**

Run `shasum -a 256 website/downloads/ZT-Monitor-Android.apk`; write the exact lowercase digest into `android.sha256`. Re-run the Node manifest test and add a check that the digest matches the file bytes.

**Step 5: Run full verification**

Run:

```bash
cd app && flutter analyze && flutter test
cd .. && npm run verify
```

Expected: all commands PASS. If iOS tooling remains blocked, report it separately; Android verification must still be complete.

**Step 6: Commit**

```bash
git add website/downloads/ZT-Monitor-Android.apk website/app-update.json website/downloads/README.md tests/website/mobileAppUpdateManifest.test.js
git commit -m "build(android): publish v1.0.0 website APK"
```

### Task 7: Final consistency and security review

**Files:**
- Inspect: all modified files
- Inspect: `app/ohos/build-profile.json5`

**Step 1: Verify no secrets are staged**

Run: `git diff --cached --check && git status --short && git ls-files app/android/key.properties '*.jks' '*.keystore'`

Expected: no key property file or keystore is tracked.

**Step 2: Verify update trust boundaries**

Confirm the update request never uses `settings.hubUrl`, never attaches Hub credentials, only accepts HTTPS, and store builds cannot invoke the direct APK channel.

**Step 3: Report the existing HarmonyOS credential exposure separately**

Do not change or repeat the secrets during this feature. Report that `app/ohos/build-profile.json5` contains plaintext signing material and recommend immediate rotation plus removal in a separately authorized security change.

**Step 4: Commit any final non-secret corrections**

```bash
git add <only-the-corrected-files>
git commit -m "chore(app): verify mobile update release"
```
