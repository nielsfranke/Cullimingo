#!/usr/bin/env bash
#
# Sign and notarize Cullimingo for macOS with the maintainer's Developer ID.
# See DISTRIBUTION.md.
#
# Usage:
#   tool/sign_macos_release.sh [--out DIR] Cullimingo-arm64.dmg [...]
#       Re-sign ad-hoc DMGs after the fact (fallback when CI didn't sign):
#       copy each app out, sign it, rebuild the DMG with tool/build_dmg.sh,
#       then finish it as below. Output keeps the input's file name, in DIR
#       (default build/macos/signed). Nothing is uploaded.
#   tool/sign_macos_release.sh --app Cullimingo.app
#       Sign one bundled app in place (CI: after tool/bundle_macos.sh).
#   tool/sign_macos_release.sh --finish Cullimingo-arm64.dmg
#       Sign, notarize and staple one DMG in place, then check it the way
#       Gatekeeper sees a download (CI: after tool/build_dmg.sh).
#
# Apps are signed inside-out (bundled dylibs, frameworks, then the app with
# Release.entitlements), all with the hardened runtime and a secure timestamp.
#
# Credentials, never from the repo; values are never printed. Either:
#   CI:    APPLE_CERTIFICATE (base64 .p12 with private key),
#          APPLE_CERTIFICATE_PASSWORD, APPLE_API_KEY_BASE64 (base64 .p8),
#          APPLE_API_KEY, APPLE_API_ISSUER — imported into a temporary
#          keychain that is deleted on exit;
#   local: $CULLIMINGO_SIGNING_ENV (default ~/.config/cullimingo/signing.env)
#          exporting APPLE_SIGNING_IDENTITY (name or SHA-1; the hash when two
#          certificates share a name), APPLE_API_ISSUER, APPLE_API_KEY and
#          APPLE_API_KEY_PATH (the .p8).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
ENTITLEMENTS="$ROOT/macos/Runner/Release.entitlements"
NAME=Cullimingo

mode=repackage
out="build/macos/signed"
targets=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --app) mode=app; shift ;;
    --finish) mode=finish; shift ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) targets+=("$1"); shift ;;
  esac
done
[[ ${#targets[@]} -gt 0 ]] || { echo "error: nothing to sign (--help)" >&2; exit 1; }

work="$(mktemp -d)"
keychain=""
cleanup() {
  hdiutil detach -quiet "$work/mnt" 2>/dev/null || true
  if [[ -n "$keychain" ]]; then
    security delete-keychain "$keychain" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

if [[ -n "${APPLE_CERTIFICATE:-}" ]]; then
  for v in APPLE_CERTIFICATE_PASSWORD APPLE_API_KEY_BASE64 APPLE_API_KEY APPLE_API_ISSUER; do
    [[ -n "${!v:-}" ]] || { echo "error: APPLE_CERTIFICATE is set but $v is not" >&2; exit 1; }
  done
  keychain="$work/signing.keychain-db"
  kc_pass="$(uuidgen)"
  security create-keychain -p "$kc_pass" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$kc_pass" "$keychain"
  base64 --decode >"$work/cert.p12" <<<"$APPLE_CERTIFICATE"
  security import "$work/cert.p12" -k "$keychain" -P "$APPLE_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign >/dev/null
  rm -f "$work/cert.p12"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$kc_pass" "$keychain" >/dev/null
  # codesign only finds identities in keychains on the search list.
  # shellcheck disable=SC2046
  security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')
  APPLE_SIGNING_IDENTITY="$(security find-identity -v -p codesigning "$keychain" |
    awk '/Developer ID Application/ { print $2; exit }')"
  [[ -n "$APPLE_SIGNING_IDENTITY" ]] || { echo "error: no Developer ID Application identity in APPLE_CERTIFICATE" >&2; exit 1; }
  APPLE_API_KEY_PATH="$work/AuthKey.p8"
  base64 --decode >"$APPLE_API_KEY_PATH" <<<"$APPLE_API_KEY_BASE64"
else
  env_file="${CULLIMINGO_SIGNING_ENV:-$HOME/.config/cullimingo/signing.env}"
  [[ -r "$env_file" ]] || { echo "error: no signing env at $env_file" >&2; exit 1; }
  # shellcheck disable=SC1090
  source "$env_file"
fi
for v in APPLE_SIGNING_IDENTITY APPLE_API_ISSUER APPLE_API_KEY APPLE_API_KEY_PATH; do
  [[ -n "${!v:-}" ]] || { echo "error: no $v" >&2; exit 1; }
done
[[ -r "$APPLE_API_KEY_PATH" ]] || { echo "error: API key file unreadable" >&2; exit 1; }
matches=$(security find-identity -v -p codesigning | grep -cF "$APPLE_SIGNING_IDENTITY" || true)
[[ "$matches" == 1 ]] || {
  echo "error: APPLE_SIGNING_IDENTITY matches $matches valid identities (want 1; use the hash)" >&2
  exit 1
}

# codesign, quiet unless it fails ("replacing existing signature" per file).
sign() {
  local log
  if ! log=$(codesign --force --timestamp --options runtime \
    --sign "$APPLE_SIGNING_IDENTITY" "$@" 2>&1); then
    echo "$log" >&2
    return 1
  fi
}

is_macho() { file -b "$1" | grep -q '^Mach-O'; }

# Paths deepest first, so nested code is signed before what contains it.
deepest_first() { awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-; }

sign_app() {
  local app="$1" f fw bin
  echo "    signing $(lipo -archs "$app/Contents/MacOS/$NAME") app"
  # 1. Loose Mach-O files (the bundled libvips/LibRaw tree in Contents/libs,
  #    plus anything else outside a framework).
  while IFS= read -r f; do
    [[ "$f" == "$app/Contents/MacOS/$NAME" ]] && continue
    is_macho "$f" && sign "$f"
  done < <(find "$app/Contents" -type f -not -path '*.framework/*' | deepest_first)
  # 2. Frameworks (Flutter, App, plugins): nested Mach-Os first, then the
  #    bundle itself, which signs its main binary.
  while IFS= read -r fw; do
    bin="$(basename "$fw" .framework)"
    while IFS= read -r f; do
      is_macho "$f" && sign "$f"
    done < <(find "$fw" -type f -not -path "$fw/Versions/*/$bin" -not -path "$fw/$bin")
    sign "$fw"
  done < <(find "$app/Contents" -type d -name '*.framework' | deepest_first)
  # 3. The app, with its entitlements.
  sign --entitlements "$ENTITLEMENTS" "$app"
  codesign --verify --deep --strict "$app"
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
  spctl -a -t open --context context:primary-signature "$probe" 2>/dev/null || rc=1
  xcrun stapler validate -q "$probe" || rc=1
  mnt="$work/mnt-verify"
  mkdir -p "$mnt"
  hdiutil attach -readonly -nobrowse -mountpoint "$mnt" "$probe" >/dev/null
  spctl -a -t exec -vv "$mnt/$NAME.app" 2>&1 | sed 's/^/    /'
  spctl -a -t exec "$mnt/$NAME.app" 2>/dev/null || rc=1
  hdiutil detach -quiet "$mnt"
  rm -f "$probe"
  return $rc
}

finish_dmg() {
  local dmg="$1"
  codesign --force --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$dmg"
  notarize "$dmg"
  xcrun stapler staple -q "$dmg"
  verify "$dmg"
  echo "    ok: $dmg"
}

case "$mode" in
  app)
    for app in "${targets[@]}"; do sign_app "$app"; done
    ;;
  finish)
    for dmg in "${targets[@]}"; do echo "==> $(basename "$dmg")"; finish_dmg "$dmg"; done
    ;;
  repackage)
    mkdir -p "$out"
    for dmg in "${targets[@]}"; do
      base="$(basename "$dmg")"
      echo "==> $base"
      mkdir -p "$work/mnt"
      hdiutil attach -readonly -nobrowse -mountpoint "$work/mnt" "$dmg" >/dev/null
      rm -rf "$work/$NAME.app"
      ditto "$work/mnt/$NAME.app" "$work/$NAME.app"
      hdiutil detach -quiet "$work/mnt"
      sign_app "$work/$NAME.app"
      # build_dmg.sh names the DMG after the app's architecture.
      built="$(tool/build_dmg.sh "$work/$NAME.app" 2>/dev/null | sed -n 's/^==> Done: \(.*\) (.*)$/\1/p')"
      mv "$built" "$out/$base"
      finish_dmg "$out/$base"
    done
    ;;
esac
