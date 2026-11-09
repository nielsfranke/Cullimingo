#!/usr/bin/env bash
#
# Sign and notarize the macOS DMGs that CI built (unsigned, ad hoc) with the
# maintainer's Developer ID, on this Mac. CI keeps building; no Apple
# credential ever reaches GitHub. See DISTRIBUTION.md.
#
# Usage:
#   tool/sign_macos_release.sh [--out DIR] Cullimingo-arm64.dmg [...]
#
# Each DMG's app is copied out, every Mach-O in it re-signed inside-out with
# the hardened runtime and a secure timestamp (Release.entitlements on the
# app), repackaged by tool/build_dmg.sh, the DMG signed, notarized, stapled
# and checked the way Gatekeeper sees a download. Output keeps the input's
# file name, in DIR (default build/macos/signed). Nothing is uploaded.
#
# Credentials come from $CULLIMINGO_SIGNING_ENV (default
# ~/.config/cullimingo/signing.env), never from the repo:
#   APPLE_SIGNING_IDENTITY  "Developer ID Application: … (TEAMID)" or its
#                           SHA-1 hash (use the hash if names are ambiguous)
#   APPLE_API_ISSUER, APPLE_API_KEY, APPLE_API_KEY_PATH
#                           App Store Connect team API key for notarytool
# Their values are never printed.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"
NAME=Cullimingo

out="build/macos/signed"
dmgs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) dmgs+=("$1"); shift ;;
  esac
done
[[ ${#dmgs[@]} -gt 0 ]] || { echo "error: no DMG given (--help)" >&2; exit 1; }

env_file="${CULLIMINGO_SIGNING_ENV:-$HOME/.config/cullimingo/signing.env}"
[[ -r "$env_file" ]] || { echo "error: no signing env at $env_file" >&2; exit 1; }
# shellcheck disable=SC1090
source "$env_file"
for v in APPLE_SIGNING_IDENTITY APPLE_API_ISSUER APPLE_API_KEY APPLE_API_KEY_PATH; do
  [[ -n "${!v:-}" ]] || { echo "error: $env_file sets no $v" >&2; exit 1; }
done
[[ -r "$APPLE_API_KEY_PATH" ]] || { echo "error: API key file unreadable" >&2; exit 1; }
matches=$(security find-identity -v -p codesigning | grep -cF "$APPLE_SIGNING_IDENTITY" || true)
[[ "$matches" == 1 ]] || {
  echo "error: APPLE_SIGNING_IDENTITY matches $matches valid identities (want 1; use the hash)" >&2
  exit 1
}

sign() {
  codesign --force --timestamp --options runtime \
    --sign "$APPLE_SIGNING_IDENTITY" "$@"
}

is_macho() { file -b "$1" | grep -q '^Mach-O'; }

sign_app() {
  local app="$1" f fw
  # 1. Loose Mach-O files (the bundled libvips/LibRaw tree in Contents/libs,
  #    plus anything else outside a framework), deepest first.
  while IFS= read -r f; do
    [[ "$f" == "$app/Contents/MacOS/$NAME" ]] && continue
    is_macho "$f" && sign "$f" >/dev/null
  done < <(find "$app/Contents" -type f -not -path '*.framework/*' | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
  # 2. Frameworks (Flutter, App, plugins): nested Mach-Os first, then the
  #    bundle itself, innermost bundles first.
  while IFS= read -r fw; do
    while IFS= read -r f; do
      is_macho "$f" && sign "$f" >/dev/null
    done < <(find "$fw" -type f -not -path "$fw/Versions/*/$(basename "$fw" .framework)" \
      -not -path "$fw/$(basename "$fw" .framework)")
    sign "$fw" >/dev/null
  done < <(find "$app/Contents" -type d -name '*.framework' | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
  # 3. The app, with its entitlements.
  sign --entitlements "$ENTITLEMENTS" "$app"
  codesign --verify --deep --strict --verbose=1 "$app"
}

notarize() {
  local dmg="$1" json id status
  json=$(xcrun notarytool submit "$dmg" \
    --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER" \
    --wait --timeout 30m --output-format json)
  id=$(plutil -extract id raw -o - - <<<"$json")
  status=$(plutil -extract status raw -o - - <<<"$json")
  echo "    notarization $id: $status"
  if [[ "$status" != Accepted ]]; then
    xcrun notarytool log "$id" \
      --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY" --issuer "$APPLE_API_ISSUER" >&2 || true
    return 1
  fi
}

# Gatekeeper as a browser download sees it: quarantined DMG and app.
verify() {
  local dmg="$1" probe mnt rc=0
  probe="$work/probe-$(basename "$dmg")"
  cp "$dmg" "$probe"
  xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$probe"
  spctl -a -t open --context context:primary-signature -vv "$probe" 2>&1 | sed 's/^/    /'
  xcrun stapler validate -q "$probe" || rc=1
  mnt="$work/mnt-verify"
  mkdir -p "$mnt"
  hdiutil attach -readonly -nobrowse -mountpoint "$mnt" "$probe" >/dev/null
  spctl -a -t exec -vv "$mnt/$NAME.app" 2>&1 | sed 's/^/    /'
  spctl -a -t exec "$mnt/$NAME.app" 2>/dev/null || rc=1
  hdiutil detach -quiet "$mnt"
  return $rc
}

work="$(mktemp -d)"
trap 'hdiutil detach -quiet "$work/mnt" 2>/dev/null || true; rm -rf "$work"' EXIT
mkdir -p "$out"

for dmg in "${dmgs[@]}"; do
  base="$(basename "$dmg")"
  echo "==> $base"
  mkdir -p "$work/mnt"
  hdiutil attach -readonly -nobrowse -mountpoint "$work/mnt" "$dmg" >/dev/null
  rm -rf "$work/$NAME.app"
  ditto "$work/mnt/$NAME.app" "$work/$NAME.app"
  hdiutil detach -quiet "$work/mnt"

  echo "    signing $(lipo -archs "$work/$NAME.app/Contents/MacOS/$NAME") app"
  sign_app "$work/$NAME.app"

  # build_dmg.sh names the DMG after the app's architecture.
  built="$(tool/build_dmg.sh "$work/$NAME.app" | sed -n 's/^==> Done: \(.*\) (.*)$/\1/p')"
  codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$built"
  mv "$built" "$out/$base"

  notarize "$out/$base"
  xcrun stapler staple -q "$out/$base"
  verify "$out/$base"
  echo "    ok: $out/$base"
done
