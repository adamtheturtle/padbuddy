#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generator="$repo_root/scripts/release-notes.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cd "$fixture"
git init -q
git config user.email test@example.com
git config user.name Test
# The fixture must not depend on the developer's signing setup.
git config commit.gpgsign false
git config tag.gpgsign false
git commit --allow-empty -qm initial
git tag v1.0.0
git commit --allow-empty -qm 'Render ![tracker](https://example.com/pixel) <img src=x> & text'
git tag v1.1.0

notes="$($generator v1.0.0 v1.1.0)"
printf '%s\n' "$notes" | grep -Fq '<code>Render ![tracker](https://example.com/pixel) &lt;img src=x&gt; &amp; text</code>'

git switch -qc unrelated v1.0.0
git commit --allow-empty -qm unrelated
git tag unrelated-tag
if "$generator" unrelated-tag v1.1.0 >/dev/null 2>&1; then
  echo "expected unrelated release boundaries to fail" >&2
  exit 1
fi

# The notes are capped so a first release on a channel — where the range is the whole
# history — cannot exceed GitHub's release-body limit (issue #4754).
for _ in $(seq 1 8); do
  git commit --allow-empty -qm "Bulk commit"
done
capped="$(RELEASE_NOTES_MAX_SUBJECTS=3 "$generator" v1.0.0 HEAD)"
listed="$(printf '%s\n' "$capped" | grep -c '^- <code>' || true)"
if [ "$listed" -ne 3 ]; then
  echo "expected 3 listed commits, got $listed" >&2
  exit 1
fi
printf '%s\n' "$capped" | grep -q 'earlier commit(s) not listed' || {
  echo "expected a truncation notice" >&2
  exit 1
}
# The newest commits are the ones kept.
printf '%s\n' "$capped" | grep -q 'Bulk commit' || {
  echo "expected the most recent commits to be listed" >&2
  exit 1
}

# An uncapped run below the limit says nothing about truncation.
if RELEASE_NOTES_MAX_SUBJECTS=500 "$generator" v1.0.0 HEAD | grep -q 'not listed'; then
  echo "did not expect a truncation notice below the cap" >&2
  exit 1
fi

if RELEASE_NOTES_MAX_SUBJECTS=0 "$generator" v1.0.0 HEAD >/dev/null 2>&1; then
  echo "expected a zero cap to be rejected" >&2
  exit 1
fi

echo "Release-notes tests passed."
