#!/usr/bin/env bash
# Publish the Cullimingo repo to the public GitHub mirror WITHOUT the private
# pre-1.0 development history.
#
# The public GitHub history starts fresh at 1.0 (a single squashed root commit),
# then each post-1.0 commit is appended. Forgejo keeps the full private history;
# this only ever pushes ONE-WAY to GitHub — never edit the GitHub repo directly.
#
# Subcommands:
#   init [VERSION]     One-time: create the squashed 1.0 root from the current
#                      main tip and push it to an (empty) GitHub repo. Records
#                      the boundary so `sync` knows where post-1.0 history starts.
#   sync               Append new commits (since the last sync) to GitHub main.
#                      Normally a fast-forward push — no force, stable SHAs.
#   release [VERSION]  Tag the current GitHub main tip as vVERSION and push it,
#                      which triggers .github/workflows/release.yml → a Release
#                      (what the in-app update check reads).
#
# Notes:
#   * Run from THIS working clone — it keeps two local marker refs between runs:
#       refs/tags/gh-public-root   the squashed 1.0 root commit (fixed)
#       refs/tags/gh-synced        the Forgejo-main commit last mirrored
#   * Needs a git credential for github.com and, for `init`, an already-created
#     empty GitHub repo (no auto-init README/license).
#   * VERSION defaults to pubspec.yaml's `version:` (build metadata dropped).
#   * Assumes linear history since the last sync (no merge commits in the range).
#   * Forgejo-only dev docs in MIRROR_EXCLUDE (below) are kept private — they are
#     stripped from every commit pushed to GitHub, so they never reach the mirror.
#   * The wiki syncs on its own: Forgejo pull-mirrors niels/Cullimingo (wiki
#     git data included) from GitHub, so no separate wiki push step is needed.
set -euo pipefail

GITHUB_URL="${GITHUB_URL:-https://github.com/nielsfranke/Cullimingo.git}"
PUBLIC_BRANCH="github-main" # local branch holding the public history
ROOT_TAG="gh-public-root"   # marks the squashed 1.0 root commit
SYNCED_TAG="gh-synced"      # marks the last Forgejo-main commit mirrored

# Forgejo-only dev docs: kept private, stripped from every commit pushed to
# GitHub. (BUILD_PLAN.md deliberately stays public — the README and 100+ source
# comments cite it.)
MIRROR_EXCLUDE=(CLAUDE.md RELEASING.md)

die() {
  echo "publish_github: $*" >&2
  exit 1
}

confirm() {
  read -r -p "$1 [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || die "aborted."
}

# Drop the Forgejo-only dev docs from the index + worktree (no-op if absent).
# During a cherry-pick this also clears an excluded file's unmerged entry, so a
# modify/delete conflict on it resolves to "not published".
strip_private() {
  git rm -rf --quiet --ignore-unmatch "${MIRROR_EXCLUDE[@]}" >/dev/null 2>&1 || true
}

# Cherry-pick one commit onto the public branch, guaranteeing the excluded docs
# never land in it (added → dropped; modified/deleted → conflict auto-resolved
# to absent). Returns non-zero only on a real conflict outside the excluded set.
replay_commit() {
  local c="$1"
  if git cherry-pick "$c" >/dev/null 2>&1; then
    strip_private
    git diff --cached --quiet || git commit -q --amend --no-edit
    return 0
  fi
  strip_private
  if git ls-files -u | grep -q .; then
    git cherry-pick --abort >/dev/null 2>&1 || true
    return 1
  fi
  if git diff --cached --quiet; then
    git cherry-pick --skip >/dev/null 2>&1 # the commit only touched excluded docs
  else
    GIT_EDITOR=true git cherry-pick --continue >/dev/null 2>&1
  fi
  return 0
}

pubspec_version() {
  local line
  line="$(grep -m1 '^version:' pubspec.yaml)" || die "no version in pubspec.yaml"
  echo "${line#version:}" | tr -d ' ' | cut -d+ -f1
}

require_repo_root_and_clean() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo."
  [[ -f pubspec.yaml ]] || die "run from the repo root."
  git diff --quiet && git diff --cached --quiet || die "working tree not clean."
}

ensure_remote() {
  if git remote get-url github >/dev/null 2>&1; then
    git remote set-url github "$GITHUB_URL"
  else
    git remote add github "$GITHUB_URL"
  fi
}

cmd_init() {
  require_repo_root_and_clean
  local version="${1:-$(pubspec_version)}"
  git rev-parse --verify --quiet "refs/tags/$ROOT_TAG" >/dev/null &&
    die "$ROOT_TAG already exists — already initialised? use 'sync'."

  local base
  base="$(git rev-parse HEAD)"
  echo "Publishing v$version from $(git rev-parse --short HEAD) as a fresh root."
  ensure_remote
  confirm "Create the squashed 1.0 root and push it to $GITHUB_URL (main)?"

  # Orphan = no parents → pushes exactly one commit, dragging no private history.
  # `checkout --orphan` keeps the working tree (unlike `switch --orphan`).
  git checkout --orphan "$PUBLIC_BRANCH"
  git add -A
  strip_private # keep the Forgejo-only dev docs out of the public mirror
  git commit -q -m "Cullimingo $version"
  git tag -f "$ROOT_TAG" >/dev/null           # the fixed public root (HEAD)
  git tag -f "$SYNCED_TAG" "$base" >/dev/null # the boundary on real history

  git push -u github "$PUBLIC_BRANCH:main"
  git switch -q main
  echo "Initialised. Now cut the release tag: $0 release $version"
}

cmd_sync() {
  require_repo_root_and_clean
  git rev-parse --verify --quiet "refs/tags/$SYNCED_TAG" >/dev/null ||
    die "not initialised — run '$0 init' first."

  local range="$SYNCED_TAG..main"
  local n
  n="$(git rev-list --count "$range")"
  [[ "$n" -gt 0 ]] || {
    echo "Nothing new to sync."
    return 0
  }
  echo "Appending $n new commit(s) to GitHub main:"
  git --no-pager log --oneline "$range"

  # Replay the new commits onto the existing public branch (append-only, a
  # fast-forward push — no force), stripping the excluded dev docs from each.
  # Linear history assumed (no merge commits in the range).
  git switch -q "$PUBLIC_BRANCH"
  local c
  for c in $(git rev-list --reverse "$range"); do
    replay_commit "$c" && continue
    git switch -q main
    die "cherry-pick conflict outside the excluded docs on ${c:0:9} — resolve by hand."
  done

  confirm "Push $n commit(s) to $GITHUB_URL (main)?"
  git push github "$PUBLIC_BRANCH:main"
  git tag -f "$SYNCED_TAG" main >/dev/null
  git switch -q main
  echo "Synced $n commit(s)."
}

cmd_release() {
  require_repo_root_and_clean
  local version="${1:-$(pubspec_version)}"
  ensure_remote
  git rev-parse --verify --quiet "refs/heads/$PUBLIC_BRANCH" >/dev/null ||
    die "no $PUBLIC_BRANCH branch — run 'init'/'sync' first."

  local tip
  tip="$(git rev-parse "$PUBLIC_BRANCH")"
  echo "Tagging GitHub main tip ${tip:0:9} as v$version (fires release.yml)."
  confirm "Create and push tag v$version to $GITHUB_URL?"
  # Local marker kept under a gh- prefix so it can't clash with a Forgejo v-tag
  # of the same name; the remote ref is the real vVERSION.
  git tag -f "gh-v$version" "$tip" >/dev/null
  git push github "$tip:refs/tags/v$version"
  echo "Released v$version on GitHub."
}

case "${1:-}" in
  init)
    shift
    cmd_init "${1:-}"
    ;;
  sync) cmd_sync ;;
  release)
    shift
    cmd_release "${1:-}"
    ;;
  *) die "usage: $0 {init [VERSION]|sync|release [VERSION]}" ;;
esac
