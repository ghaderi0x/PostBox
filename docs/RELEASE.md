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

Install the release APK on a real device or emulator and test: launch, send a request, secure storage, OAuth redirect (intent filter), rotation, Persian UI, R8-stripped code paths. Adaptive icon: generate from `assets/branding/logo.svg`.

Play listing text and the Data Safety summary are in `docs/PLAY_STORE.md`; the privacy policy is `docs/PRIVACY_POLICY.md` (publish it on a public URL).

## Windows (build on Windows only)

```
flutter build windows --release
```

Installer: install Inno Setup 6 and compile `packaging/postbox.iss` (output in `build/installer`). Test on a clean machine or VM, including the OAuth loopback redirect and Windows Defender SmartScreen behaviour for an unsigned installer. MSIX is an alternative (the `msix` package); not configured.

## Linux (build on Linux only)

```
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev
flutter build linux --release
./packaging/build_deb.sh 0.2.0
./packaging/build_appimage.sh 0.2.0     # needs appimagetool
```

Runtime needs `libsecret-1-0` and a keyring service (GNOME Keyring, KWallet) for persistent secrets; without them PostBox keeps secrets in memory and warns.

## CI

`.github/workflows/ci.yml` formats, analyzes and tests on every push, then builds Linux, Windows and Android on their own runners and uploads the bundles. It generates platform folders with the setup script when they are not committed.

## Definition of release-ready

Every artifact above built **and** tested on its platform, with the result recorded per platform in `PROJECT_STATUS.md`.
