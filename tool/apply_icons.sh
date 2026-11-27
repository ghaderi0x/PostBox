#!/usr/bin/env bash
# Applies the PostBox icon to every platform folder that exists, replacing
# Flutter's default icon. Run from the repository root after
# tool/setup_platforms.sh, then commit the changes:
#   bash tool/apply_icons.sh
set -euo pipefail

# Android (launcher icons) and Windows (.ico) via flutter_launcher_icons.
if [ -d android ] || [ -d windows ]; then
  dart run flutter_launcher_icons
fi
# Windows: make sure the exe icon is ours even if the generator skipped it.
if [ -d windows/runner/resources ]; then
  cp assets/branding/app_icon.ico windows/runner/resources/app_icon.ico
fi

# macOS: the icon set uses these file names (Flutter template).
ICONSET=macos/Runner/Assets.xcassets/AppIcon.appiconset
if [ -d "$ICONSET" ]; then
  for size in 16 32 64 128 256 512 1024; do
    if command -v sips >/dev/null 2>&1; then
      sips -z "$size" "$size" assets/branding/logo.png --out "$ICONSET/app_icon_${size}.png" >/dev/null
    elif command -v convert >/dev/null 2>&1; then
      convert assets/branding/logo.png -resize "${size}x${size}" "$ICONSET/app_icon_${size}.png"
    else
      echo "macOS icons skipped: install ImageMagick (convert) or run this script on a Mac." && break
    fi
  done
fi

echo "Icons applied. Run: flutter clean && flutter build ..."
echo "Commit: git add -A && git commit -m 'Apply app icons'"
