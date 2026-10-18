#!/usr/bin/env bash
# One-time setup: generate the Android, Windows and Linux runner projects and
# apply the PostBox-specific Android changes. Run from the repository root.
# On Windows use Git Bash or WSL, or follow docs/RELEASE.md by hand.
set -euo pipefail

flutter create --org com.uniqueone --project-name postbox --platforms android,windows,linux .

# `flutter create` adds the counter-app widget test, which does not match this app.
rm -f test/widget_test.dart

MANIFEST=android/app/src/main/AndroidManifest.xml

if ! grep -q 'android.permission.INTERNET' "$MANIFEST"; then
  # Release builds need INTERNET in the main manifest (the template only adds it to debug).
  sed -i '0,/<application/s//<uses-permission android:name="android.permission.INTERNET"\/>\n    <application/' "$MANIFEST"
fi

if ! grep -q 'oauth2redirect' "$MANIFEST"; then
  # OAuth redirect: com.uniqueone.postbox:/oauth2redirect
  sed -i '0,/<\/activity>/s//    <intent-filter>\n                <action android:name="android.intent.action.VIEW"\/>\n                <category android:name="android.intent.category.DEFAULT"\/>\n                <category android:name="android.intent.category.BROWSABLE"\/>\n                <data android:scheme="com.uniqueone.postbox" android:path="\/oauth2redirect"\/>\n            <\/intent-filter>\n        <\/activity>/' "$MANIFEST"
fi

echo
echo "Done. Next:"
echo "  1. Edit android/app/build.gradle(.kts): targetSdk 36, minSdk 24, signing and R8 (docs/RELEASE.md)."
echo "  2. flutter pub get && dart format . && flutter analyze && flutter test"
