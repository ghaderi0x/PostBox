#!/usr/bin/env bash
# Builds a drag-to-Applications disk image from the Flutter macOS bundle.
# Run on a Mac after `flutter build macos --release`:
#   ./packaging/build_dmg.sh 1.0.0
# The image is NOT signed or notarised. Gatekeeper will ask the user to
# confirm on first launch (right-click > Open). See docs/RELEASE.md.
set -euo pipefail
VERSION="${1:-1.0.0}"
OUT="build/dmg"
APP=$(find build/macos/Build/Products/Release -maxdepth 1 -name '*.app' | head -n 1)
[ -n "$APP" ] || { echo "No .app found. Run: flutter build macos --release"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT/stage"
cp -R "$APP" "$OUT/stage/PostBox.app"
ln -s /Applications "$OUT/stage/Applications"

hdiutil create \
  -volname "PostBox $VERSION" \
  -srcfolder "$OUT/stage" \
  -ov -format UDZO \
  "$OUT/PostBox-$VERSION-macos.dmg"

rm -rf "$OUT/stage"
echo "Created $OUT/PostBox-$VERSION-macos.dmg"
