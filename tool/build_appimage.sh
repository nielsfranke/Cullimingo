#!/usr/bin/env bash
#
# Wraps the self-contained Linux bundle (see tool/bundle_linux.sh) as a single
# portable AppImage (BUILD_PLAN.md §6.1). Run AFTER `flutter build linux
# --release` and `tool/bundle_linux.sh`, so <bundle>/lib carries libraw/libvips
# + the vips-heif module + libheif plugins.
#
# Usage:
#   tool/build_appimage.sh [path/to/bundle]
# Defaults to the release bundle. Produces build/linux/Cullimingo-x86_64.AppImage.
#
# We hand-write AppRun (no linuxdeploy) to stay consistent with bundle_linux.sh:
# native codecs are bundled, but glibc/GTK/X11/GL core is left to the host — so
# the AppImage targets a normal Linux desktop, not a bare container. appimagetool
# is fetched on first run and cached; it runs via --appimage-extract-and-run so
# building needs no FUSE (running the *result* still wants FUSE, or run it with
# --appimage-extract-and-run).
set -euo pipefail

cd "$(dirname "$0")/.."
BUNDLE="${1:-build/linux/x64/release/bundle}"
APP=cullimingo
NAME=Cullimingo
ICON_SRC=assets/branding/cullimingo_icon_256.png
OUT=build/linux/${NAME}-x86_64.AppImage

if [[ ! -x "$BUNDLE/$APP" ]]; then
  echo "error: bundle not found at $BUNDLE/$APP" >&2
  echo "build it first: flutter build linux --release && tool/bundle_linux.sh" >&2
  exit 1
fi
if [[ ! -e "$BUNDLE/lib/libvips.so.42" ]]; then
  echo "error: $BUNDLE not bundled yet — run tool/bundle_linux.sh first" >&2
  exit 1
fi

APPDIR="build/linux/${NAME}.AppDir"
echo "==> Assembling $APPDIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr"
cp -a "$BUNDLE/." "$APPDIR/usr/"

# Icon at the AppDir root (appimagetool requirement) + the hicolor theme path.
cp "$ICON_SRC" "$APPDIR/$APP.png"
install -Dm644 "$ICON_SRC" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps/$APP.png"

cat > "$APPDIR/$APP.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$NAME
Comment=Fast cross-platform photo culling
Exec=$APP
Icon=$APP
Categories=Graphics;Photography;
Terminal=false
EOF

# AppRun execs the bundled binary from its real location, so Flutter's
# \$ORIGIN/lib rpath and VipsEncoder's exe-relative VIPSHOME/LIBHEIF_PLUGIN_PATH
# all resolve inside the mounted AppImage.
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/cullimingo" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Fetch appimagetool once, cached under ~/.cache.
TOOL_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cullimingo"
TOOL="$TOOL_DIR/appimagetool-x86_64.AppImage"
if [[ ! -x "$TOOL" ]]; then
  echo "==> Fetching appimagetool"
  mkdir -p "$TOOL_DIR"
  curl -fsSL -o "$TOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi

echo "==> Building $OUT"
# --appimage-extract-and-run: build without FUSE (CI / headless hosts).
ARCH=x86_64 "$TOOL" --appimage-extract-and-run "$APPDIR" "$OUT"

size=$(du -h "$OUT" | cut -f1)
echo "==> Done: $OUT ($size)"
echo "    Run it directly, or with --appimage-extract-and-run if FUSE is absent."
