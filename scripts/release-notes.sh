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

if [ -n "$FROM" ]; then
  if ! git merge-base --is-ancestor "$FROM^{commit}" "$TO^{commit}"; then
    echo "error: from-ref '$FROM' is not an ancestor of '$TO'" >&2
    exit 64
  fi
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
# Bounded. The initial-release fallback is every commit reachable from the target ref,
# which is the normal state for the first tag on a channel — so the first `appstore-v*`
# release rendered one bullet per commit in the repository's entire history. GitHub caps a
# release body at 125,000 characters, so `gh release create --notes-file` rejects it and
# the release step fails *after* the build has been signed and notarized. The ordinary
# two-tag case is bounded too, which matters for a channel that has been quiet a long
# while (issue #4754).
MAX_SUBJECTS="${RELEASE_NOTES_MAX_SUBJECTS:-300}"
if [[ ! "$MAX_SUBJECTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: RELEASE_NOTES_MAX_SUBJECTS must be a positive integer, got '$MAX_SUBJECTS'" >&2
  exit 64
fi

TOTAL="$(git log --no-merges --pretty=format:'%s' "$RANGE" | grep -c '' || true)"
# Newest first for the cap, then reversed back to oldest-first for display, so the
# commits that are dropped are the oldest rather than the most recent.
LOG="$(git log --no-merges --max-count="$MAX_SUBJECTS" --pretty=format:'%s' "$RANGE" \
  | sed '1!G;h;$!d')"
if [ -n "$LOG" ]; then
  if [ "$TOTAL" -gt "$MAX_SUBJECTS" ]; then
    printf -- '_… and %s earlier commit(s) not listed._\n\n' "$((TOTAL - MAX_SUBJECTS))"
  fi
  while IFS= read -r subject; do
    escaped="$(printf '%s' "$subject" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')"
    printf -- '- <code>%s</code>\n' "$escaped"
  done <<< "$LOG"
  echo
else
  echo "_No changes._"
fi
