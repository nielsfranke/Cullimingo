#!/usr/bin/env bash
#
# Bundle the native libvips + libraw shared objects (and their non-system
# dependency tree) into a built Flutter Linux bundle so it runs without
# `apt install libraw-bin libvips42` (BUILD_PLAN.md §6.1).
#
# This is the Linux analogue of tool/bundle_macos.sh. Where macOS uses
# dylibbundler + @executable_path, here we copy each .so next to Flutter's own
# libs in <bundle>/lib and set RUNPATH=$ORIGIN with patchelf, so the loader
# resolves the whole tree from that directory. The Dart loaders
# (core/native/bundled_libs.dart) prefer <bundle>/lib over the system paths.
#
# Usage:
#   tool/bundle_linux.sh [path/to/bundle]
# Defaults to the release build. Re-run after every `flutter build linux`.
#
# Requires: patchelf, ldd, ldconfig (all standard on Debian/Ubuntu; patchelf via
# `apt install patchelf`).

set -euo pipefail

BUNDLE="${1:-build/linux/x64/release/bundle}"
LIBS_DIR="$BUNDLE/lib"

if [[ ! -d "$BUNDLE" ]]; then
  echo "error: bundle not found: $BUNDLE" >&2
  echo "build it first, e.g. 'flutter build linux --release'" >&2
  exit 1
fi
for tool in patchelf ldd ldconfig; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: $tool not found (apt install patchelf)" >&2
    exit 1
  fi
done

mkdir -p "$LIBS_DIR"

# Roots we dlopen directly; their transitive deps are pulled in below.
ROOTS=(libraw.so libvips.so.42)

# System libs to leave to the host loader — bundling glibc/X11/GL/GTK core would
# break more than it fixes (they must match the running kernel/driver stack).
# Everything else libvips/libraw drags in (jpeg, tiff, png, exif, lcms, …) is
# copied so the app is self-contained.
is_system_lib() {
  case "$1" in
    ld-linux*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|\
    libresolv.so*|libgcc_s.so*|libstdc++.so*|\
    libGL*.so*|libEGL*.so*|libGLdispatch*.so*|libGLX*.so*|libdrm*.so*|\
    libX11*.so*|libxcb*.so*|libXext*.so*|libXi*.so*|libXrandr*.so*|\
    libwayland*.so*|libgtk-3.so*|libgdk-3.so*|libglib-2.0.so*|\
    libgobject-2.0.so*|libgio-2.0.so*|libgmodule-2.0.so*|libpango*.so*|\
    libcairo*.so*|libgdk_pixbuf*.so*|libharfbuzz*.so*|libfontconfig*.so*|\
    libfreetype*.so*)
      return 0 ;;
    *) return 1 ;;
  esac
}

# Absolute path of a soname via the dynamic linker cache.
resolve_soname() {
  # No early `exit` in awk: exiting on the first match closes the pipe while
  # ldconfig is still writing, handing it a SIGPIPE that `set -o pipefail`
  # turns into a fatal 141 on some hosts (seen on Arch, a race elsewhere).
  # Read all input and print the last match — there's normally only one.
  ldconfig -p | awk -v n="$1" '$1==n {found=$NF} END {print found}'
}

echo "==> Bundling native libs into $LIBS_DIR"

declare -A copied=()
copy_with_deps() {
  local src="$1"
  local base; base="$(basename "$src")"
  [[ -n "${copied[$base]:-}" ]] && return
  copied[$base]=1
  cp -Lf "$src" "$LIBS_DIR/$base"
  chmod u+w "$LIBS_DIR/$base"
  patchelf --set-rpath '$ORIGIN' "$LIBS_DIR/$base"

  # Recurse into this lib's own dependencies. `ldd` prints "soname => /path
  # (addr)" for resolved deps; the awk keeps only those, dropping the vdso and
  # the loader line (which have no "=>").
  while read -r name path; do
    [[ "$path" != /* ]] && continue
    is_system_lib "$name" && continue
    copy_with_deps "$path"
  done < <(ldd "$LIBS_DIR/$base" 2>/dev/null | awk '$2=="=>" {print $1, $3}')
}

for root in "${ROOTS[@]}"; do
  src="$(resolve_soname "$root")"
  if [[ -z "$src" || ! -e "$src" ]]; then
    echo "error: $root not found in ldconfig cache" >&2
    echo "       install it, e.g. 'apt install libraw-dev libvips-dev'" >&2
    exit 1
  fi
  copy_with_deps "$src"
done

# AVIF is a vips *runtime module* (not linked into libvips.so.42 like WebP).
# vips searches for modules at `$VIPSHOME/<arch>/vips-modules-<ver>/`, where
# <arch> is the LAST path component of vips' compiled-in libdir — on Debian/
# Ubuntu that's the multiarch triple (e.g. `x86_64-linux-gnu`), NOT `lib`. So
# the module must sit at `<bundle>/<arch>/…`, not under `lib/`. (macOS Homebrew
# has libdir basename `lib`, which is why bundle_macos.sh puts it under libs/.)
# At runtime VipsEncoder sets VIPSHOME=<bundle>. Missing module → the app just
# doesn't offer AVIF.
vips_libdir="$(pkg-config --variable=libdir vips 2>/dev/null ||
  dirname "$(resolve_soname libvips.so.42)")"
arch="$(basename "$vips_libdir")"
for moddir in "$vips_libdir"/vips-modules-*; do
  [[ -e "$moddir/vips-heif.so" ]] || continue
  modname="$(basename "$moddir")"
  dest="$BUNDLE/$arch/$modname"
  mkdir -p "$dest"
  cp -Lf "$moddir/vips-heif.so" "$dest/vips-heif.so"
  chmod u+w "$dest/vips-heif.so"
  # From <bundle>/<arch>/vips-modules-<ver>/ back to <bundle>/lib is two up.
  patchelf --set-rpath '$ORIGIN/../../lib' "$dest/vips-heif.so"
  while read -r name path; do
    [[ "$path" != /* ]] && continue
    is_system_lib "$name" && continue
    copy_with_deps "$path"
  done < <(ldd "$dest/vips-heif.so" 2>/dev/null | awk '$2=="=>" {print $1, $3}')

  # libheif itself dlopens its codec backends from a plugin dir (aom encoder
  # for AVIF). Bundle them + their libaom/libde265 into
  # <bundle>/lib/libheif/plugins/; VipsEncoder sets LIBHEIF_PLUGIN_PATH there.
  plugin_src="$vips_libdir/libheif/plugins"
  if [[ -d "$plugin_src" ]]; then
    plugin_dest="$LIBS_DIR/libheif/plugins"
    mkdir -p "$plugin_dest"
    for plug in "$plugin_src"/*.so; do
      [[ -e "$plug" ]] || continue
      cp -Lf "$plug" "$plugin_dest/$(basename "$plug")"
      chmod u+w "$plugin_dest/$(basename "$plug")"
      # plugins live at lib/libheif/plugins → deps at lib is two up.
      patchelf --set-rpath '$ORIGIN/../..' "$plugin_dest/$(basename "$plug")"
      while read -r name path; do
        [[ "$path" != /* ]] && continue
        is_system_lib "$name" && continue
        copy_with_deps "$path"
      done < <(ldd "$plugin_dest/$(basename "$plug")" 2>/dev/null |
        awk '$2=="=>" {print $1, $3}')
    done
  fi
done

count=$(find "$LIBS_DIR" -maxdepth 1 -name '*.so*' | wc -l | tr -d ' ')
size=$(du -sh "$LIBS_DIR" | cut -f1)
echo "==> Done: $count shared objects ($size) in $LIBS_DIR"
echo "    The bundle now carries libraw/libvips and their non-system deps."
