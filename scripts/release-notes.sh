#!/usr/bin/env bash
#
# Generate Markdown release notes from the git log between two refs.
#
# Usage:
#   scripts/release-notes.sh [<from-ref>] [<to-ref>]
#
# Defaults:
#   <to-ref>   HEAD
#   <from-ref> the most recent tag reachable before <to-ref> (the previous
#              release); if there is no earlier tag, the full history is used.
#
# Examples:
#   scripts/release-notes.sh                 # previous tag → HEAD
#   scripts/release-notes.sh v1.0.0          # v1.0.0 → HEAD
#   scripts/release-notes.sh v1.0.0 v1.1.0   # between two tags
#
# Intended for the GitHub Releases body on a tag push; prints to stdout so it
# can be redirected to a file or piped to `gh release create --notes-file -`.
set -euo pipefail

TO="${2:-HEAD}"

if [ -n "${1:-}" ]; then
  FROM="$1"
else
  # Keep the two release channels independent. Infer App Store notes from the
  # destination ref (or the Actions tag); direct releases use v* tags.
  RELEASE_REF="${GITHUB_REF_NAME:-$TO}"
  if [[ "$RELEASE_REF" == appstore-v* ]]; then
    TAG_PATTERN="appstore-v[0-9]*"
  else
    TAG_PATTERN="v[0-9]*"
  fi
  # Most recent same-channel tag strictly before TO; empty if none (first release).
  FROM="$(git describe --tags --match "$TAG_PATTERN" --abbrev=0 "${TO}^" 2>/dev/null || true)"
fi

# Derive owner/repo from the origin remote so we can link a compare view.
REMOTE_URL="$(git config --get remote.origin.url 2>/dev/null || echo '')"
case "$REMOTE_URL" in
  git@github.com:*) SLUG="${REMOTE_URL#git@github.com:}" ;;
  https://github.com/*) SLUG="${REMOTE_URL#https://github.com/}" ;;
  ssh://git@github.com/*) SLUG="${REMOTE_URL#ssh://git@github.com/}" ;;
  *) SLUG="" ;;
esac
SLUG="${SLUG%.git}"

if [ -n "$FROM" ]; then
  RANGE="${FROM}..${TO}"
  echo "## Changes (${FROM} → ${TO})"
else
  RANGE="$TO"
  echo "## Changes (initial release)"
fi
echo

# Non-merge commit subjects, oldest first, as bullet points. `%s` is the subject
# line only, so commit-message bodies and trailers (e.g. Co-Authored-By) are
# omitted from the notes.
if git log --no-merges --reverse --pretty=format:'- %s' "$RANGE" | grep -q .; then
  git log --no-merges --reverse --pretty=format:'- %s' "$RANGE"
  echo
else
  echo "_No changes._"
fi

if [ -n "$SLUG" ] && [ -n "$FROM" ]; then
  echo
  echo "**Full diff:** https://github.com/${SLUG}/compare/${FROM}...${TO}"
fi
