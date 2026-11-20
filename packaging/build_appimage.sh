#!/usr/bin/env bash
# Builds an AppImage from the Flutter Linux bundle. Unverified: needs
# appimagetool (https://github.com/AppImage/appimagetool) on PATH, run on Linux
# after `flutter build linux --release`. libsecret must exist on the target.
set -euo pipefail
VERSION="${1:-1.0.0}"
BUNDLE="build/linux/x64/release/bundle"
APPDIR="build/appimage/PostBox.AppDir"

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
cp -r "$BUNDLE"/* "$APPDIR/usr/bin/"
cp assets/branding/logo_512.png "$APPDIR/postbox.png"

cat > "$APPDIR/postbox.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=PostBox
Exec=postbox
Icon=postbox
Categories=Development;Network;
DESKTOP

cat > "$APPDIR/AppRun" <<'RUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "$HERE/usr/bin/postbox" "$@"
RUN
chmod +x "$APPDIR/AppRun"

ARCH=x86_64 appimagetool "$APPDIR" "build/appimage/PostBox-${VERSION}-x86_64.AppImage"
