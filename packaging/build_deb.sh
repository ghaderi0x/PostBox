#!/usr/bin/env bash
# Builds a .deb from the Flutter Linux bundle. Unverified: run on Debian/Ubuntu
# after `flutter build linux --release`. Needs dpkg-deb.
set -euo pipefail
VERSION="${1:-1.0.0}"
ARCH="${2:-amd64}"
BUNDLE="build/linux/x64/release/bundle"
ROOT="build/deb/postbox_${VERSION}_${ARCH}"

rm -rf "$ROOT"
mkdir -p "$ROOT/DEBIAN" "$ROOT/opt/postbox" "$ROOT/usr/bin" "$ROOT/usr/share/applications" "$ROOT/usr/share/icons/hicolor/512x512/apps"
cp -r "$BUNDLE"/* "$ROOT/opt/postbox/"
ln -s /opt/postbox/postbox "$ROOT/usr/bin/postbox"
cp assets/branding/logo_512.png "$ROOT/usr/share/icons/hicolor/512x512/apps/com.uniqueone.postbox.png"

cat > "$ROOT/usr/share/applications/com.uniqueone.postbox.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=PostBox
Comment=Open-source, local-first HTTP API client
Exec=/opt/postbox/postbox
Icon=com.uniqueone.postbox
Categories=Development;Network;
Terminal=false
DESKTOP

cat > "$ROOT/DEBIAN/control" <<CONTROL
Package: postbox
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: ${ARCH}
Maintainer: Uniqueone <ghaderi0x@users.noreply.github.com>
Homepage: https://github.com/ghaderi0x/PostBox
Depends: libgtk-3-0, libsecret-1-0, gnome-keyring | libsecret-1-0
Description: PostBox, a local-first HTTP API client
 Open-source API client with collections, environments, OAuth 2.0 and
 English/Persian interface. Secrets are stored in the system keyring.
CONTROL

dpkg-deb --build --root-owner-group "$ROOT"
echo "Built ${ROOT}.deb"
