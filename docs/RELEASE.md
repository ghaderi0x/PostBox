# Release engineering

**Nothing here has been run.** Follow it on real machines and record results in `PROJECT_STATUS.md`.

## 0. One-time project setup

```
./tool/setup_platforms.sh        # Git Bash / WSL on Windows
flutter pub get
dart format . && flutter analyze && flutter test
```

## Android

`applicationId` is `com.uniqueone.postbox` (set by `--org com.uniqueone --project-name postbox`).

**Target SDK.** Google Play requires new apps and updates to target Android 16 (API 36) from 2026-08-31 (checked 2026-10-18; confirm in Play Console before release). Set `targetSdk = 36` and `minSdk = 24` in `android/app/build.gradle.kts`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.uniqueone.postbox"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.uniqueone.postbox"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true      // R8
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

Copy `android_overlay/proguard-rules.pro` to `android/app/`.

**Upload keystore** (never commit it or `key.properties`; both are in `.gitignore`):

```
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
cp android_overlay/key.properties.example android/key.properties   # then edit
```

**Build and test**

```
flutter build appbundle --release        # build/app/outputs/bundle/release/app-release.aab
flutter build apk --release              # for installing on a device
```

Install the release APK on a real device or emulator and test: launch, send a request, secure storage, OAuth redirect (intent filter), rotation, Persian UI, R8-stripped code paths. Icons: run `dart run flutter_launcher_icons` (Android adaptive icon and Windows .ico from `assets/branding`) and `dart run flutter_native_splash:create` once after the platform folders exist.

Play listing text and the Data Safety summary are in `docs/PLAY_STORE.md`; the privacy policy is `docs/PRIVACY_POLICY.md` (publish it on a public URL).

### Startup crash after a release build (R8)

Symptom: the app opens to "PostBox could not start" with `NoSuchMethodError: no non-static method ... SharedPreferencesApiRegistrar.getAll(...)` (or a similar plugin class). Cause: R8 shrinking/optimizing the plugin's Kotlin coroutine code. Fix:

1. Copy `android_overlay/proguard-rules.pro` to `android/app/proguard-rules.pro` (it keeps the plugin classes) and make sure `proguardFiles(...)` in `build.gradle.kts` lists it.
2. Append `android_overlay/gradle.properties.append` to `android/gradle.properties` (turns off R8 full mode).
3. To confirm R8 is the cause, temporarily set `isMinifyEnabled = false` and `isShrinkResources = false`, rebuild, and check that the app starts.
4. Uninstall the old app from the phone first, then `flutter clean && flutter build apk --release`.

## Windows (build on Windows only)

```
flutter build windows --release
```

Installer: install Inno Setup 6 and compile `packaging/postbox.iss` (output in `build/installer`). Test on a clean machine or VM, including the OAuth loopback redirect and Windows Defender SmartScreen behaviour for an unsigned installer. MSIX is an alternative (the `msix` package); not configured.

## Linux (build on Linux only)

```
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev
flutter build linux --release
./packaging/build_deb.sh 1.0.0
./packaging/build_appimage.sh 1.0.0     # needs appimagetool
```

Runtime needs `libsecret-1-0` and a keyring service (GNOME Keyring, KWallet) for persistent secrets; without them PostBox keeps secrets in memory and warns.

## Publishing a release (and what the in-app updater sees)

1. `tool/bump_version.sh 1.2.0` (updates pubspec, `app_info.dart`, the installer script and the version test) and add a `## 1.2.0` entry to `CHANGELOG.md`.
2. Commit, then `git tag v1.2.0 && git push origin main v1.2.0`.
3. `.github/workflows/release.yml` checks that the tag matches `pubspec.yaml`, runs analyze and tests, builds `PostBox-1.2.0-windows-setup.exe`, `PostBox-1.2.0-macos.dmg`, `postbox_1.2.0_amd64.deb` and `PostBox-1.2.0-x86_64.AppImage`, writes `SHA256SUMS.txt` and publishes the GitHub Release with the CHANGELOG section as notes.
4. Android: build the APK/AAB yourself and upload it to the release, Myket and Bazaar.

The app calls `https://api.github.com/repos/ghaderi0x/PostBox/releases/latest` once per start (switch: Settings > About). Pre-releases and drafts are never offered. The updater picks the asset by file name (`*setup*.exe`, `*.deb`, `*.AppImage`) and verifies it against `SHA256SUMS.txt`, so keep those names. Installers are not code-signed yet, so Windows SmartScreen will warn; add signing before wide distribution.

### App icon is still the Flutter logo

`flutter create` (run by `tool/setup_platforms.sh`) generates Flutter's default icon. Run `bash tool/apply_icons.sh` once after setup (Android launcher icons, Windows `.ico`, macOS icon set), then commit the changed files. If the `windows/` or `macos/` folders are committed, the release workflow does not regenerate them, so this step must be committed too. On a phone, uninstall the old app so Android refreshes its icon cache.

### Android build error: "compiled against android-33"

If `flutter build apk --release` fails with `:desktop_drop:checkReleaseAarMetadata ... requires libraries and applications that depend on it to compile against version 34 or later`, a plugin is compiling against an old SDK. `tool/setup_platforms.sh` adds the fix to `android/build.gradle.kts`; to add it by hand, put this at the very top of that file (above the `evaluationDependsOn(":app")` block):

```kotlin
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android")
        if (androidExt is com.android.build.gradle.BaseExtension) {
            androidExt.compileSdkVersion(36)
        }
    }
}
```

### macOS

`tool/setup_platforms.sh` creates the `macos/` runner, adds the sandbox entitlements PostBox needs (network client, network server for the OAuth redirect, user-selected files) and generates the app icon. `packaging/build_dmg.sh` wraps `build/macos/Build/Products/Release/*.app` in a drag-to-Applications `.dmg`.

The image is **not signed or notarised**. Users must right-click the app and choose *Open* the first time. To remove that step you need an Apple Developer account: sign with a *Developer ID Application* certificate and notarise with `xcrun notarytool` (store the certificate and credentials as repository secrets and add the steps to the `macos` job). Also check on a real Mac that secrets are saved in the Keychain: `flutter_secure_storage` may need a signed build or the `keychain-access-groups` entitlement. Default shortcuts use Ctrl, not Cmd.

## CI

`.github/workflows/ci.yml` formats, analyzes and tests on every push, then builds Linux, Windows and Android on their own runners and uploads the bundles. It generates platform folders with the setup script when they are not committed.

## Definition of release-ready

Every artifact above built **and** tested on its platform, with the result recorded per platform in `PROJECT_STATUS.md`.
