#!/usr/bin/env bash
# Mirror the Forgejo wiki to the GitHub wiki.
#
# Forgejo's built-in repository push-mirror covers the code repo + tags, but a
# wiki is a *separate* git repo (`<repo>.wiki.git`) that the push-mirror does
# NOT include. So run this (or wire it into a cron job / Forgejo Action) to keep
# the public GitHub wiki in sync with the Forgejo one.
#
# One-time setup on the GitHub side: the GitHub wiki repo only exists once the
# wiki has been initialised — create any page in the repo's Wiki tab in the web
# UI once, or the first push below fails with "repository not found".
#
# Auth: pushing to GitHub needs a credential. Either have a git credential
# helper configured for github.com, or set GITHUB_WIKI_URL to an authenticated
# remote, e.g.
#   GITHUB_WIKI_URL="https://<user>:<token>@github.com/nielsfranke/Cullimingo.wiki.git" \
#     tool/mirror_wiki.sh
#
# Source: set FORGEJO_WIKI_URL to your private Forgejo wiki remote (e.g. export it
# from your shell profile); the default below is a non-functional placeholder.
set -euo pipefail

FORGEJO_WIKI_URL="${FORGEJO_WIKI_URL:-https://forgejo.example.com/<user>/Cullimingo.wiki.git}"
GITHUB_WIKI_URL="${GITHUB_WIKI_URL:-https://github.com/nielsfranke/Cullimingo.wiki.git}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Cloning Forgejo wiki: $FORGEJO_WIKI_URL"
git clone --bare "$FORGEJO_WIKI_URL" "$work/wiki.git"

echo "Pushing to GitHub wiki: ${GITHUB_WIKI_URL%%:*}…"
# Branch mismatch: Forgejo serves wikis from `main`, but GitHub renders its wiki
# from `master`. A plain `push --mirror` would push `main` and DELETE `master`,
# leaving the GitHub wiki showing an empty "Pages" list. So map main → master
# with a force push (one-way, Forgejo → GitHub — never edit the GitHub wiki
# directly; it's overwritten on the next run). Force-replacing master's tip with
# main's is an "exact copy" for the content branch: pages deleted on Forgejo are
# gone from the pushed tree too.
git -C "$work/wiki.git" push --force "$GITHUB_WIKI_URL" \
  "refs/heads/main:refs/heads/master"

echo "Wiki mirrored."
