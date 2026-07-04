#!/usr/bin/env bash
#
# Package the bundled Cullimingo.app into a drag-to-install .dmg
# (BUILD_PLAN.md §6.1). Run AFTER `flutter build macos --release` and
# tool/bundle_macos.sh, so the .app is self-contained (native dylibs bundled).
#
# Usage:
#   tool/build_dmg.sh [path/to/Cullimingo.app]
# Defaults to the release build. Produces build/macos/Cullimingo-<arch>.dmg.
#
# The DMG holds the .app + an /Applications symlink, so opening it shows the
# familiar "drag Cullimingo to Applications" window. The app is still UNSIGNED
# (ad-hoc) — see DISTRIBUTION.md for the one-time `xattr -cr` a user runs.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${1:-build/macos/Build/Products/Release/Cullimingo.app}"
NAME=Cullimingo
ARCH="$(uname -m)" # arm64 on Apple Silicon
OUT="build/macos/${NAME}-${ARCH}.dmg"

if [[ ! -d "$APP" ]]; then
  echo "error: app not found: $APP" >&2
  echo "build + bundle it first: flutter build macos --release && tool/bundle_macos.sh" >&2
  exit 1
fi

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

cp -R "$APP" "$staging/$NAME.app"
ln -s /Applications "$staging/Applications" # the drag target

mkdir -p build/macos
rm -f "$OUT"
# UDZO = zlib-compressed, read-only — the standard distributable DMG format.
hdiutil create \
  -volname "$NAME" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$OUT"

size=$(du -h "$OUT" | cut -f1)
echo "==> Done: $OUT ($size)"
