#!/usr/bin/env bash
# Usage: tool/bump_version.sh 1.2.0 [build]
# Updates every place that holds the version. Run from the repository root,
# then commit and push a tag: git tag v1.2.0 && git push origin v1.2.0
set -euo pipefail
V="${1:?version like 1.2.0}"
B="${2:-}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.0"; exit 1; }
if [ -z "$B" ]; then
  CUR=$(grep -E '^version:' pubspec.yaml | sed -E 's/.*\+([0-9]+).*/\1/')
  B=$((CUR + 1))
fi
sed -i -E "s/^version: .*/version: ${V}+${B}/" pubspec.yaml
sed -i -E "s/^const String appBuild = '.*';/const String appBuild = '${B}';/" lib/core/app_info.dart
sed -i -E "s/^const String appVersion = '.*';/const String appVersion = '${V}';/" lib/core/app_info.dart
sed -i -E "s/#define AppVersion \".*\"/#define AppVersion \"${V}\"/" packaging/postbox.iss
sed -i -E "s/VERSION=\"\\$\{1:-[0-9.]+\}\"/VERSION=\"\${1:-${V}}\"/" packaging/build_deb.sh packaging/build_appimage.sh packaging/build_dmg.sh
sed -i -E "s/'v[0-9]+\.[0-9]+\.[0-9]+'/'v${V}'/" test/ui/widgets_test.dart
echo "Version is now ${V}+${B}. Add a CHANGELOG.md entry, commit, then tag v${V}."
