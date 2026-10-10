#!/usr/bin/env bash
#
# Build the native RAW/preview stack (LibRaw + libvips and their dependency
# tree) from source for one macOS architecture, into a private prefix that
# tool/bundle_macos.sh then bundles instead of Homebrew's.
#
# Why: the Intel .dmg needs x86_64 dylibs, and Homebrew no longer ships Intel
# bottles (Tier 3 since Homebrew 7.0). We cross-compile on Apple Silicon, so
# the build doesn't need an Intel machine or GitHub's Intel runners (retired in
# 2027). Build-time helpers (glib's code generators) run under Rosetta.
#
# The feature set mirrors the Flatpak (flatpak/flatpak-flutter.yml): libvips
# gets JPEG/PNG/WebP/HEIF/EXIF/LCMS only — what the app's FFI calls use — with
# HEIF linked in (no runtime modules). System zlib/expat/libffi/iconv come from
# the SDK.
#
# Usage:
#   tool/build_macos_deps.sh [x86_64|arm64]       # default: x86_64
# Output: build/macos-deps/<arch>/prefix. Needs: brew install meson ninja nasm
# cmake pkg-config. Re-running skips finished libraries (stamps in the prefix);
# delete build/macos-deps/<arch> to start over.
set -euo pipefail

cd "$(dirname "$0")/.."
ARCH="${1:-x86_64}"
MIN_MACOS="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
ROOT="$PWD/build/macos-deps"
SRC="$ROOT/src" # downloads, shared by both archs
WORK="$ROOT/$ARCH/work"
PREFIX="$ROOT/$ARCH/prefix"
STAMPS="$PREFIX/.stamps"
JOBS="$(sysctl -n hw.ncpu)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

case "$ARCH" in
  x86_64) TRIPLE=x86_64-apple-darwin ;;
  arm64) TRIPLE=aarch64-apple-darwin ;;
  *)
    echo "error: unknown arch $ARCH (x86_64 or arm64)" >&2
    exit 1
    ;;
esac
for tool in meson ninja cmake nasm pkg-config; do
  command -v "$tool" >/dev/null || {
    echo "error: $tool not found — brew install meson ninja cmake nasm pkg-config" >&2
    exit 1
  }
done

mkdir -p "$SRC" "$WORK" "$PREFIX/lib/pkgconfig" "$STAMPS"

# Only our prefix is visible to pkg-config (and CMake, see cmake_build):
# Homebrew's (arm64) libraries must never leak into this build.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH
export MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS"

ARCH_FLAGS="-arch $ARCH -mmacosx-version-min=$MIN_MACOS -isysroot $SDK"
export CC="clang $ARCH_FLAGS" CXX="clang++ $ARCH_FLAGS"
export CFLAGS="-O2" CXXFLAGS="-O2"
export LDFLAGS="-L$PREFIX/lib -Wl,-headerpad_max_install_names"
export CPPFLAGS="-I$PREFIX/include"

# The SDK has these system libraries but no .pc files for them.
cat >"$PREFIX/lib/pkgconfig/libffi.pc" <<EOF
Name: libffi
Description: libffi (macOS SDK)
Version: 3.4.0
Libs: -lffi
Cflags: -I$SDK/usr/include/ffi
EOF
cat >"$PREFIX/lib/pkgconfig/expat.pc" <<EOF
Name: expat
Description: expat (macOS SDK)
Version: 2.5.0
Libs: -lexpat
Cflags:
EOF
cat >"$PREFIX/lib/pkgconfig/zlib.pc" <<EOF
Name: zlib
Description: zlib (macOS SDK)
Version: 1.2.12
Libs: -lz
Cflags:
EOF

CROSS="$WORK/meson-cross.ini"
cat >"$CROSS" <<EOF
[binaries]
c = ['clang', '-arch', '$ARCH']
cpp = ['clang++', '-arch', '$ARCH']
objc = ['clang', '-arch', '$ARCH']
ar = 'ar'
strip = 'strip'
pkg-config = 'pkg-config'
nasm = 'nasm'

[built-in options]
c_args = ['-mmacosx-version-min=$MIN_MACOS', '-isysroot', '$SDK', '-I$PREFIX/include']
cpp_args = ['-mmacosx-version-min=$MIN_MACOS', '-isysroot', '$SDK', '-I$PREFIX/include']
objc_args = ['-mmacosx-version-min=$MIN_MACOS', '-isysroot', '$SDK', '-I$PREFIX/include']
c_link_args = ['-mmacosx-version-min=$MIN_MACOS', '-isysroot', '$SDK', '-L$PREFIX/lib', '-Wl,-headerpad_max_install_names']
cpp_link_args = ['-mmacosx-version-min=$MIN_MACOS', '-isysroot', '$SDK', '-L$PREFIX/lib', '-Wl,-headerpad_max_install_names']
objc_link_args = ['-mmacosx-version-min=$MIN_MACOS', '-isysroot', '$SDK', '-L$PREFIX/lib', '-Wl,-headerpad_max_install_names']

[properties]
# Apple Silicon runs x86_64 helpers under Rosetta.
needs_exe_wrapper = false

[host_machine]
system = 'darwin'
subsystem = 'macos'
kernel = 'xnu'
cpu_family = '$([[ $ARCH == arm64 ]] && echo aarch64 || echo x86_64)'
cpu = '$ARCH'
endian = 'little'
EOF

# fetch <name> <url> <sha256> — download once into $SRC, verify, unpack fresh
# into $WORK/<name>, and cd there.
fetch() {
  local name="$1" url="$2" sha="$3" file
  file="$SRC/$(basename "$url")"
  if [[ ! -f "$file" ]]; then
    curl -fsSL --retry 3 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | shasum -a 256 -c --quiet - || {
    echo "error: checksum mismatch for $file" >&2
    exit 1
  }
  rm -rf "${WORK:?}/$name"
  mkdir -p "$WORK/$name"
  tar -xf "$file" -C "$WORK/$name" --strip-components 1
  cd "$WORK/$name"
}

done_() { [[ -f "$STAMPS/$1" ]]; }
mark() {
  touch "$STAMPS/$1"
  cd "$ROOT"
}

meson_build() {
  meson setup _build --cross-file "$CROSS" --prefix "$PREFIX" --libdir lib \
    --buildtype release -Ddefault_library=shared "$@"
  meson install -C _build
}

cmake_build() {
  cmake -S . -B _build -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_NAME_DIR="$PREFIX/lib" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_MACOS" \
    -DCMAKE_OSX_SYSROOT="$SDK" \
    -DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
    -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
    -DCMAKE_SYSTEM_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" \
    -DBUILD_SHARED_LIBS=ON \
    "$@"
  cmake --build _build -j "$JOBS"
  cmake --install _build
}

autotools_build() {
  ./configure --prefix="$PREFIX" --host="$TRIPLE" \
    --enable-shared --disable-static "$@"
  make -j "$JOBS"
  make install
}

echo "==> Building the native stack for $ARCH (macOS $MIN_MACOS+) into $PREFIX"

if ! done_ pcre2; then
  fetch pcre2 https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.49/pcre2-10.49.tar.bz2 \
    53c156e1ba416a20da8e65395daa132da0d80e76910424caca3fcdae7831d384
  cmake_build -DPCRE2_BUILD_PCRE2_8=ON -DPCRE2_BUILD_PCRE2_16=OFF \
    -DPCRE2_BUILD_PCRE2_32=OFF -DPCRE2_BUILD_TESTS=OFF \
    -DPCRE2_BUILD_PCRE2GREP=OFF -DPCRE2_SUPPORT_JIT=ON
  mark pcre2
fi

if ! done_ glib; then
  fetch glib https://download.gnome.org/sources/glib/2.90/glib-2.90.1.tar.xz \
    93c941aa17d5eb1d53fe838365f29a8b4e539c222a256d974ec8f30fc413e396
  # libintl isn't in the SDK: glib falls back to its proxy-libintl subproject.
  meson_build -Dtests=false -Dintrospection=disabled -Dnls=disabled \
    -Ddocumentation=false -Dman-pages=disabled -Ddtrace=disabled \
    -Dsystemtap=disabled -Dsysprof=disabled -Dlibelf=disabled
  mark glib
fi

if ! done_ jpeg; then
  fetch jpeg https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/3.2.0/libjpeg-turbo-3.2.0.tar.gz \
    6f30092cef9fb839779646608f4ee14ae3cbac989c47fa05e841b0841f09878e
  cmake_build -DENABLE_STATIC=OFF -DWITH_TURBOJPEG=OFF -DWITH_TOOLS=OFF \
    -DWITH_TESTS=OFF
  mark jpeg
fi

if ! done_ png; then
  fetch png https://downloads.sourceforge.net/project/libpng/libpng16/1.6.59/libpng-1.6.59.tar.xz \
    d80dd2a38a37f803cb9b6ac7b14bd6e74ddc3b654780a8380bdf93523fdb4389
  cmake_build -DPNG_STATIC=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF \
    -DPNG_FRAMEWORK=OFF
  mark png
fi

if ! done_ lcms2; then
  fetch lcms2 https://downloads.sourceforge.net/project/lcms/lcms/2.19.1/lcms2-2.19.1.tar.gz \
    bfc54f7bab59fbc921012014a8032e4cba4abd46db47d46b76416a8c0b2815c8
  autotools_build --without-jpeg --without-tiff
  mark lcms2
fi

if ! done_ exif; then
  fetch exif https://github.com/libexif/libexif/releases/download/v0.6.26/libexif-0.6.26.tar.bz2 \
    0830ed253fceeb60444fb309598bc8a9491d3007dc054aad3a50a347c5597c57
  autotools_build --disable-nls --disable-docs
  mark exif
fi

if ! done_ webp; then
  fetch webp https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0.tar.gz \
    e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
  cmake_build -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF \
    -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF \
    -DWEBP_BUILD_EXTRAS=OFF
  mark webp
fi

# HEIC/HIF decode (GitHub #10).
if ! done_ de265; then
  fetch de265 https://github.com/strukturag/libde265/releases/download/v1.1.3/libde265-1.1.3.tar.gz \
    554228bd17788c99a7e63b37ab5634722190e6e2bf60c1dcb01cef328e133905
  cmake_build -DENABLE_SDL=OFF -DENABLE_DECODER=OFF -DENABLE_ENCODER=OFF
  mark de265
fi

# AVIF decode.
if ! done_ dav1d; then
  fetch dav1d https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.bz2 \
    2abfb0c89212e6e4733a54e0ae509ec00a5b845a6360946f918806e14aedb011
  meson_build -Denable_tools=false -Denable_tests=false -Denable_examples=false
  mark dav1d
fi

# AVIF encode (the AVIF export).
if ! done_ aom; then
  fetch aom https://storage.googleapis.com/aom-releases/libaom-3.15.2.tar.gz \
    67bb54b245f33ed98600e08269e6139986e48114e14042474ddd8885801dfddc
  cmake_build -DAOM_TARGET_CPU="$([[ $ARCH == arm64 ]] && echo arm64 || echo x86_64)" \
    -DCONFIG_AV1_DECODER=0 -DENABLE_DOCS=OFF -DENABLE_EXAMPLES=OFF \
    -DENABLE_TESTDATA=OFF -DENABLE_TESTS=OFF -DENABLE_TOOLS=OFF
  mark aom
fi

if ! done_ heif; then
  fetch heif https://github.com/strukturag/libheif/releases/download/v1.23.6/libheif-1.23.6.tar.gz \
    4484346dc5995319dbc11e3a1c35d0a2ec46511ce370900869337fd2c7033125
  cmake_build -DENABLE_PLUGIN_LOADING=OFF -DWITH_EXAMPLES=OFF \
    -DBUILD_DOCUMENTATION=OFF -DBUILD_TESTING=OFF -DWITH_GDK_PIXBUF=OFF \
    -DWITH_LIBDE265=ON -DWITH_AOM_ENCODER=ON -DWITH_AOM_DECODER=OFF \
    -DWITH_DAV1D=ON -DWITH_X265=OFF -DWITH_X264=OFF -DWITH_OpenH264_DECODER=OFF \
    -DWITH_OpenH264_ENCODER=OFF -DWITH_RAV1E=OFF -DWITH_SvtEnc=OFF \
    -DWITH_KVAZAAR=OFF -DWITH_FFMPEG_DECODER=OFF -DWITH_OpenJPEG_DECODER=OFF \
    -DWITH_OpenJPEG_ENCODER=OFF -DWITH_JPEG_DECODER=OFF \
    -DWITH_JPEG_ENCODER=OFF -DWITH_UNCOMPRESSED_CODEC=OFF \
    -DWITH_LIBSHARPYUV=OFF -DWITH_OPENJPH_ENCODER=OFF -DWITH_OPENJPH_DECODER=OFF
  mark heif
fi

# Embedded-preview extraction and RAW decode; 0.22 is needed for Nikon
# HE/HE* NEFs. No OpenMP (Apple clang has none; Homebrew links libomp).
if ! done_ libraw; then
  fetch libraw https://www.libraw.org/data/LibRaw-0.22.2.tar.gz \
    de86b035655accff8d4010f1a221fdf50d353cb7b1422ba26f14a0db92612cfa
  autotools_build --disable-openmp --enable-jpeg --enable-lcms
  mark libraw
fi

if ! done_ vips; then
  fetch vips https://github.com/libvips/libvips/releases/download/v8.18.7/vips-8.18.7.tar.xz \
    5baaead3b0bb20ffdb9e9ff09aa9fda08620923df77b63b436654cb5e0b3bf94
  meson_build --auto-features=disabled \
    -Djpeg=enabled -Dpng=enabled -Dwebp=enabled -Dheif=enabled \
    -Dexif=enabled -Dlcms=enabled -Dzlib=enabled \
    -Dmodules=disabled -Dintrospection=disabled -Dcplusplus=false \
    -Ddeprecated=false -Dexamples=false -Ddocs=false
  mark vips
fi

# Every dylib must be $ARCH-only and must not reference Homebrew.
echo "==> Checking the result"
bad=0
while IFS= read -r f; do
  archs="$(lipo -archs "$f")"
  if [[ "$archs" != "$ARCH" ]]; then
    echo "error: $f is '$archs', expected $ARCH" >&2
    bad=1
  fi
  if otool -L "$f" | grep -qE '/opt/homebrew|/usr/local'; then
    echo "error: $f links Homebrew:" >&2
    otool -L "$f" | grep -E '/opt/homebrew|/usr/local' >&2
    bad=1
  fi
done < <(find "$PREFIX/lib" -name '*.dylib' -type f)
[[ $bad == 0 ]] || exit 1

count=$(find "$PREFIX/lib" -name '*.dylib' -type f | wc -l | tr -d ' ')
echo "==> Done: $count $ARCH dylibs in $PREFIX/lib"
