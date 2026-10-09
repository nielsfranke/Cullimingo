#!/usr/bin/env bash
#
# Builds the Cullimingo Flatpak from source (GitHub #13) for the host
# architecture and exports it to an OSTree repo plus a single-file bundle.
#
# Usage:
#   tool/build_flatpak.sh <commit> [out-dir]
#
# <commit> is the Cullimingo commit to build. The manifest's app source is
# pinned to it — flatpak/flatpak-flutter.yml carries a release tag for local
# use; this swaps that for the commit. out-dir defaults to build/flatpak and
# receives:
#   repo/                                  OSTree repo (app + Locale refs)
#   Cullimingo-<arch>.flatpak              single-file bundle
#
# Set FLATPAK_GPG_KEY (key id) and optionally FLATPAK_GPG_HOMEDIR to sign the
# exported commits; tool/publish_flatpak_repo.sh signs the repo summary.
#
# Steps: flatpak-flutter (pinned, below) generates the offline manifest —
# Flutter SDK, pub packages, Rust toolchain + crates — then flatpak-builder
# builds it in its sandbox. Needs network for the generator and for installing
# the GNOME 51 runtime/SDK and the llvm22 extension from Flathub.
#
# Requires: flatpak, flatpak-builder, git, python3 (+ venv). See
# DISTRIBUTION.md "Linux (Flatpak)".
set -euo pipefail

cd "$(dirname "$0")/.."
COMMIT="${1:?usage: tool/build_flatpak.sh <commit> [out-dir]}"
OUT="$(mkdir -p "${2:-build/flatpak}" && cd "${2:-build/flatpak}" && pwd)"
APP_ID=io.github.nielsfranke.Cullimingo
BRANCH=stable
# Pinned for reproducible manifests; bump deliberately.
FF_REPO=https://github.com/TheAppgineer/flatpak-flutter
FF_COMMIT=e59a96fcb0fcf48fcd46e8134cae64c26fdc3290

ARCH="$(flatpak --default-arch)"
WORK="$OUT/work"
rm -rf "$WORK" "$OUT/repo"
mkdir -p "$WORK"

echo "==> flatpak-flutter @ ${FF_COMMIT:0:12}"
FF_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/cullimingo/flatpak-flutter"
if [[ ! -d "$FF_DIR/.git" ]]; then
  git clone -q "$FF_REPO" "$FF_DIR"
fi
git -C "$FF_DIR" fetch -q origin
git -C "$FF_DIR" checkout -q "$FF_COMMIT"
if [[ ! -x "$FF_DIR/.venv/bin/python" ]]; then
  python3 -m venv "$FF_DIR/.venv"
fi
"$FF_DIR/.venv/bin/pip" install -q -r "$FF_DIR/requirements.txt"

echo "==> Generating the offline manifest for $COMMIT"
cp flatpak/flatpak-flutter.yml flatpak/foreign.json "$WORK/"
# Swap the app source's release tag for the exact commit.
sed -i.bak -E "s/^( +)tag: v[0-9][^ ]*$/\1commit: $COMMIT/" \
  "$WORK/flatpak-flutter.yml"
grep -q "commit: $COMMIT" "$WORK/flatpak-flutter.yml" || {
  echo "error: couldn't pin the app source to $COMMIT" >&2
  exit 1
}
(cd "$WORK" && "$FF_DIR/.venv/bin/python" "$FF_DIR/flatpak-flutter.py" \
  flatpak-flutter.yml)

echo "==> Installing build dependencies"
# Explicit installs instead of flatpak-builder's --install-deps-from, which
# also *updates* refs already present — in the CI container that update fails
# with "Invalid cross-device link" (overlayfs). Keep in sync with the
# manifest's runtime, sdk and sdk-extensions.
flatpak remote-add --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
for ref in org.gnome.Platform//51 org.gnome.Sdk//51 \
  org.freedesktop.Sdk.Extension.llvm22//26.08; do
  flatpak info "$ref" >/dev/null 2>&1 ||
    flatpak install -y --noninteractive flathub "$ref"
done

echo "==> Building $APP_ID ($ARCH)"
sign=()
if [[ -n "${FLATPAK_GPG_KEY:-}" ]]; then
  sign=(--gpg-sign="$FLATPAK_GPG_KEY")
  [[ -n "${FLATPAK_GPG_HOMEDIR:-}" ]] &&
    sign+=(--gpg-homedir="$FLATPAK_GPG_HOMEDIR")
fi
# --disable-rofiles-fuse: CI containers and Docker have no FUSE.
(cd "$WORK" && flatpak-builder --sandbox --disable-rofiles-fuse \
  --default-branch="$BRANCH" --force-clean \
  --repo="$OUT/repo" "${sign[@]}" build-dir "$APP_ID.yml")

echo "==> Bundling"
# --repo-url + --gpg-keys: installing the bundle also adds the self-hosted
# repo as the app's origin, so `flatpak update` keeps it current.
flatpak build-bundle \
  --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  --repo-url="${FLATPAK_BASE_URL:-https://nielsfranke.github.io/Cullimingo}/repo/" \
  --gpg-keys=flatpak/cullimingo-repo.gpg \
  "$OUT/repo" "$OUT/Cullimingo-$ARCH.flatpak" "$APP_ID" "$BRANCH"

echo "==> Done: $OUT/repo + Cullimingo-$ARCH.flatpak"
