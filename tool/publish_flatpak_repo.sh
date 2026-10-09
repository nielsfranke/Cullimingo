#!/usr/bin/env bash
#
# Assembles the self-hosted Flatpak repo site (GitHub #13) from the per-arch
# repos tool/build_flatpak.sh exports, ready to deploy to GitHub Pages:
#
#   <site>/repo/                                       signed OSTree repo
#   <site>/cullimingo.flatpakrepo                      `flatpak remote-add`
#   <site>/io.github.nielsfranke.Cullimingo.flatpakref one-click install
#   <site>/index.html                                  install instructions
#
# Usage:
#   tool/publish_flatpak_repo.sh <site-dir> <arch-repo>...
#
# Each run builds the repo fresh with just the newest commits: clients update
# from whatever they have to the new commit, so history isn't needed, and the
# Pages site stays small. Debug extensions are left out.
#
# FLATPAK_GPG_KEY (key id) and optionally FLATPAK_GPG_HOMEDIR sign the
# summary and appstream; the app commits arrive already signed by
# tool/build_flatpak.sh. The public key is flatpak/cullimingo-repo.gpg.
set -euo pipefail

cd "$(dirname "$0")/.."
SITE="${1:?usage: tool/publish_flatpak_repo.sh <site-dir> <arch-repo>...}"
shift
(($#)) || { echo "error: no arch repos given" >&2; exit 1; }
APP_ID=io.github.nielsfranke.Cullimingo
BASE_URL="${FLATPAK_BASE_URL:-https://nielsfranke.github.io/Cullimingo}"
PUBKEY=flatpak/cullimingo-repo.gpg

rm -rf "$SITE"
mkdir -p "$SITE"
ostree init --mode=archive-z2 --repo="$SITE/repo"

for src in "$@"; do
  for ref in $(ostree refs --repo="$src" | grep -E '^(app|runtime)/' |
    grep -v '\.Debug/'); do
    echo "==> $ref"
    ostree pull-local --repo="$SITE/repo" "$src" "$ref"
  done
done

sign=()
if [[ -n "${FLATPAK_GPG_KEY:-}" ]]; then
  sign=(--gpg-sign="$FLATPAK_GPG_KEY")
  [[ -n "${FLATPAK_GPG_HOMEDIR:-}" ]] &&
    sign+=(--gpg-homedir="$FLATPAK_GPG_HOMEDIR")
fi
flatpak build-update-repo --title=Cullimingo --default-branch=stable \
  --prune "${sign[@]}" "$SITE/repo"

GPGKEY="$(base64 -w0 "$PUBKEY" 2>/dev/null || base64 < "$PUBKEY" | tr -d '\n')"

cat > "$SITE/cullimingo.flatpakrepo" <<EOF
[Flatpak Repo]
Title=Cullimingo
Url=$BASE_URL/repo/
Homepage=https://github.com/nielsfranke/Cullimingo
Comment=Fast, keyboard-first photo culling
Icon=$BASE_URL/icon.png
GPGKey=$GPGKEY
EOF

cat > "$SITE/$APP_ID.flatpakref" <<EOF
[Flatpak Ref]
Title=Cullimingo
Name=$APP_ID
Branch=stable
Url=$BASE_URL/repo/
SuggestRemoteName=cullimingo
Homepage=https://github.com/nielsfranke/Cullimingo
Icon=$BASE_URL/icon.png
RuntimeRepo=https://dl.flathub.org/repo/flathub.flatpakrepo
IsRuntime=false
GPGKey=$GPGKEY
EOF

cp assets/branding/cullimingo_icon_256.png "$SITE/icon.png"

cat > "$SITE/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>Cullimingo Flatpak</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 42rem;
         margin: 3rem auto; padding: 0 1rem; }
  code, pre { background: #f2f2f4; border-radius: 4px; }
  pre { padding: .75rem 1rem; overflow-x: auto; }
</style>
<h1><img src="icon.png" width="48" height="48" alt="" style="vertical-align:middle"> Cullimingo Flatpak</h1>
<p>Fast, keyboard-first photo culling. This is Cullimingo's own Flatpak
repository; updates arrive through <code>flatpak update</code> or your
software centre.</p>
<h2>Install</h2>
<p>Open <a href="$APP_ID.flatpakref">$APP_ID.flatpakref</a> with your
software centre, or run:</p>
<pre>flatpak install --user $BASE_URL/$APP_ID.flatpakref</pre>
<p>The runtime comes from Flathub, which is added automatically if missing.</p>
<h2>Add the repository only</h2>
<pre>flatpak remote-add --user --if-not-exists cullimingo $BASE_URL/cullimingo.flatpakrepo</pre>
<p><a href="https://github.com/nielsfranke/Cullimingo">Source, releases and
issues on GitHub</a></p>
EOF

echo "==> Site ready in $SITE"
