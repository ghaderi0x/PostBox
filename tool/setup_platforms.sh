#!/usr/bin/env bash
# One-time setup: generate the platform runner projects and apply the
# PostBox-specific changes. Run from the repository root.
#
#   ./tool/setup_platforms.sh                    # all four platforms
#   PLATFORMS=linux ./tool/setup_platforms.sh    # only some (comma separated)
#
# On Windows use Git Bash or WSL. The Android edits use GNU sed; on macOS run
# `brew install gnu-sed` first (or set PLATFORMS=macos to skip Android).
set -euo pipefail

PLATFORMS="${PLATFORMS:-android,windows,linux,macos}"
has() { [[ ",$PLATFORMS," == *",$1,"* ]]; }

flutter create --org com.uniqueone --project-name postbox --platforms "$PLATFORMS" .

# `flutter create` adds the counter-app widget test, which does not match this app.
rm -f test/widget_test.dart

if has android; then
  MANIFEST=android/app/src/main/AndroidManifest.xml

  if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
    # Release builds need INTERNET in the main manifest (the template only adds it to debug).
    sed -i '0,/<application/s//<uses-permission android:name="android.permission.INTERNET"\/>\n    <application/' "$MANIFEST"
  fi

  if ! grep -q 'oauth2redirect' "$MANIFEST"; then
    # OAuth redirect: com.uniqueone.postbox:/oauth2redirect
    sed -i '0,/<\/activity>/s//    <intent-filter>\n                <action android:name="android.intent.action.VIEW"\/>\n                <category android:name="android.intent.category.DEFAULT"\/>\n                <category android:name="android.intent.category.BROWSABLE"\/>\n                <data android:scheme="com.uniqueone.postbox" android:path="\/oauth2redirect"\/>\n            <\/intent-filter>\n        <\/activity>/' "$MANIFEST"
  fi

  if ! grep -q 'android.intent.action.SEND' "$MANIFEST"; then
    # "Share to PostBox" (text, JSON) and "Open with" for .json files.
    awk -v f=android_overlay/share_intent_filters.xml '/<\/activity>/ && !done { while ((getline line < f) > 0) print line; done=1 } { print }' "$MANIFEST" > "$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
  fi

  # Share/open-with bridge (replaces the generated MainActivity).
  KOTLIN_DIR=android/app/src/main/kotlin/com/uniqueone/postbox
  mkdir -p "$KOTLIN_DIR"
  cp android_overlay/MainActivity.kt "$KOTLIN_DIR/MainActivity.kt"
fi

if has macos; then
  # The macOS app is sandboxed. PostBox needs outgoing connections (every
  # request), a local server socket (OAuth redirect) and access to files the
  # user picks. awk keeps this portable (BSD and GNU).
  for f in macos/Runner/DebugProfile.entitlements macos/Runner/Release.entitlements; do
    [ -f "$f" ] || continue
    for key in com.apple.security.network.client \
               com.apple.security.network.server \
               com.apple.security.files.user-selected.read-write; do
      if ! grep -q "$key" "$f"; then
        awk -v k="$key" '
          { lines[NR] = $0 }
          END {
            last = 0
            for (i = NR; i >= 1; i--) if (lines[i] ~ /<\/dict>/) { last = i; break }
            for (i = 1; i <= NR; i++) {
              if (i == last) { print "\t<key>" k "</key>"; print "\t<true/>" }
              print lines[i]
            }
          }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
      fi
    done
  done
fi

if has windows; then
  # Window and exe icon.
  cp assets/branding/app_icon.ico windows/runner/resources/app_icon.ico
fi

if has macos; then
  # App icon from assets/branding/logo.png (names match the Flutter template).
  ICONSET=macos/Runner/Assets.xcassets/AppIcon.appiconset
  if [ -d "$ICONSET" ]; then
    for size in 16 32 64 128 256 512 1024; do
      if command -v sips >/dev/null 2>&1; then
        sips -z "$size" "$size" assets/branding/logo.png --out "$ICONSET/app_icon_${size}.png" >/dev/null
      elif command -v convert >/dev/null 2>&1; then
        convert assets/branding/logo.png -resize "${size}x${size}" "$ICONSET/app_icon_${size}.png"
      fi
    done
  fi
fi

echo
echo "Done. Next:"
if has android; then
  echo "  1. Edit android/app/build.gradle(.kts): targetSdk 36, minSdk 24, signing and R8 (docs/RELEASE.md)."
fi
echo "  - flutter pub get && dart format . && flutter analyze && flutter test"
if has android; then
  echo "  - Android icons: dart run flutter_launcher_icons && dart run flutter_native_splash:create"
fi
