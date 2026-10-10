#!/usr/bin/env bash
#
# Bundle the native libvips + libraw dylibs (and their whole dependency tree)
# into a built Cullimingo.app so it runs without Homebrew (BUILD_PLAN.md §6.1).
#
# Uses dylibbundler (`brew install dylibbundler`) to copy every non-system
# dependency into Contents/libs and relink it to @executable_path/../libs. The
# Dart loaders (core/native/bundled_libs.dart) prefer that bundle over Homebrew.
#
# The .app is thinned to ONE architecture, the one the bundled dylibs are built
# for: a universal app with arm64-only dylibs starts on an Intel Mac but can't
# load LibRaw there, so every RAW stays a grey placeholder. Thinned, the wrong
# build is refused by macOS up front.
#
# Usage:
#   tool/bundle_macos.sh [path/to/Cullimingo.app]
# Defaults to the release build. Re-run after every `flutter build macos`.
#
# Environment:
#   CULLIMINGO_MACOS_ARCH  arm64 | x86_64 (default: this Mac's arch)
#   CULLIMINGO_DEPS_LIB    lib dir holding libvips/libraw for that arch
#                          (default: Homebrew's). The Intel build uses
#                          tool/build_macos_deps.sh's prefix, e.g.
#                          build/macos-deps/x86_64/prefix/lib.
#
# The result is UNSIGNED (ad-hoc). See DISTRIBUTION.md for how end users open it.

set -euo pipefail

APP="${1:-build/macos/Build/Products/Release/Cullimingo.app}"

if [[ ! -d "$APP" ]]; then
  echo "error: app not found: $APP" >&2
  echo "build it first, e.g. 'flutter build macos --release'" >&2
  exit 1
fi
if ! command -v dylibbundler >/dev/null 2>&1; then
  echo "error: dylibbundler not found — run 'brew install dylibbundler'" >&2
  exit 1
fi

ARCH="${CULLIMINGO_MACOS_ARCH:-$(uname -m)}"
DEPS_LIB="${CULLIMINGO_DEPS_LIB:-$(brew --prefix 2>/dev/null || echo /opt/homebrew)/lib}"
LIBS_DIR="$APP/Contents/libs"

# ditto --arch drops the other slice from every universal Mach-O (runner,
# Flutter engine, plugins). Their signatures are redone at the end.
echo "==> Thinning the app to $ARCH"
thin="$(mktemp -d)"
ditto --arch "$ARCH" "$APP" "$thin/app"
rm -rf "$APP"
mv "$thin/app" "$APP"
rmdir "$thin"

# Roots we dlopen directly; dylibbundler pulls in the rest of the tree.
ROOTS=(libvips.42.dylib libraw.dylib)

echo "==> Bundling into $LIBS_DIR"
rm -rf "$LIBS_DIR"
mkdir -p "$LIBS_DIR"

fix_args=()
for root in "${ROOTS[@]}"; do
  src="$DEPS_LIB/$root"
  if [[ ! -e "$src" ]]; then
    echo "error: $src missing — 'brew install vips libraw' (arm64) or" \
      "tool/build_macos_deps.sh (x86_64)" >&2
    exit 1
  fi
  cp -L "$src" "$LIBS_DIR/$root"
  chmod u+w "$LIBS_DIR/$root"
  fix_args+=(-x "$LIBS_DIR/$root")
done

# AVIF support is a vips *runtime module* (not linked into libvips.42.dylib
# like WebP). Bundle it + let dylibbundler pull its deps (libheif, aom, …).
# At runtime VipsEncoder points VIPSHOME at Contents/vipshome, whose lib/
# symlink makes vips find $VIPSHOME/lib/vips-modules-<ver>/. Missing module
# is fine — the app then simply doesn't offer AVIF (probe in VipsEncoder).
for moddir in "$DEPS_LIB"/vips-modules-*; do
  [[ -e "$moddir/vips-heif.dylib" ]] || continue
  modname="$(basename "$moddir")"
  mkdir -p "$LIBS_DIR/$modname"
  cp -L "$moddir/vips-heif.dylib" "$LIBS_DIR/$modname/vips-heif.dylib"
  chmod u+w "$LIBS_DIR/$modname/vips-heif.dylib"
  fix_args+=(-x "$LIBS_DIR/$modname/vips-heif.dylib")
  mkdir -p "$APP/Contents/vipshome"
  ln -sfn ../libs "$APP/Contents/vipshome/lib"
done

dylibbundler -of -b \
  "${fix_args[@]}" \
  -s "$DEPS_LIB" \
  -d "$LIBS_DIR/" \
  -p "@executable_path/../libs/"

# dylibbundler adds `@executable_path/../libs/` as an LC_RPATH once per
# dependency edge it rewrites, so a lib pulled in by many others ends up with
# the SAME rpath repeated (libvips had it 31×). Modern dyld (macOS 15+) rejects
# a "duplicate LC_RPATH" and refuses to load the dylib — i.e. the app wouldn't
# launch on a clean Mac. Collapse each file's copies back to one.
echo "==> De-duplicating LC_RPATH entries"
RPATH='@executable_path/../libs/'
while IFS= read -r f; do
  # `grep -c` exits 1 on zero matches, which under `set -eo pipefail` would
  # abort the whole script at the first dylib that lacks this rpath (e.g.
  # libdatrie) — leaving later dylibs un-deduped and skipping the final
  # codesign. `|| true` keeps the count at 0 and the loop alive.
  n=$(otool -l "$f" 2>/dev/null | grep -c "path $RPATH " || true)
  while [[ "$n" -gt 1 ]]; do
    install_name_tool -delete_rpath "$RPATH" "$f" 2>/dev/null || break
    n=$((n - 1))
  done
done < <(find "$LIBS_DIR" -name '*.dylib')

# `install_name_tool` (dedup above) rewrites the Mach-O in place, which
# invalidates each touched dylib's code signature. `codesign --deep` on the app
# does NOT re-sign loose dylibs under the non-standard Contents/libs — it only
# recurses into Frameworks/PlugIns — so those stay "code or signature have been
# modified" and dyld SIGKILLs the app with "Code Signature Invalid" the moment
# it loads one (e.g. the OpenEXR/de265 tree on the first HEIF/AVIF encode).
# Every bundled dylib must carry the app's architecture — one that doesn't
# fails to load at runtime, silently (RAWs just stay placeholders).
echo "==> Checking bundled dylibs are $ARCH"
wrong=0
while IFS= read -r f; do
  if ! lipo "$f" -verify_arch "$ARCH" 2>/dev/null; then
    echo "error: $f lacks $ARCH ($(lipo -archs "$f"))" >&2
    wrong=1
  fi
done < <(find "$LIBS_DIR" -name '*.dylib')
[[ $wrong == 0 ]] || exit 1

# Re-sign every bundled dylib ad-hoc before sealing the app.
echo "==> Ad-hoc re-signing bundled dylibs"
find "$LIBS_DIR" -name '*.dylib' -print0 | xargs -0 codesign --force --sign -

# Re-sign the whole app ad-hoc so the modified bundle is internally consistent.
echo "==> Ad-hoc re-signing the app"
codesign --force --deep --sign - "$APP"

count=$(find "$LIBS_DIR" -name '*.dylib' | wc -l | tr -d ' ')
size=$(du -sh "$LIBS_DIR" | cut -f1)
echo "==> Done: $ARCH app, $count dylibs ($size) in Contents/libs"
echo "    The .app is now self-contained (no Homebrew needed) but UNSIGNED."
echo "    See DISTRIBUTION.md for opening it on another Mac."
