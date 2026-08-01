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

echo "Release-notes tests passed."
