#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generator="$repo_root/scripts/generate-appcast.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
printf archive > update.zip

for tag in '../latest' 'v1.2?x' 'v1.2#x' 'v01.2.0' 'release-1.2.0'; do
  if env SPARKLE_PRIVATE_ED_KEY=test "$generator" "$tag" update.zip >/dev/null 2>&1; then
    echo "expected invalid tag '$tag' to fail" >&2
    exit 1
  fi
done

for origin in 'http://example.com' 'https://user@example.com' 'https://example.com/path' \
  'https://example.com?query' 'https://example.com#fragment'; do
  if env GITHUB_SERVER_URL="$origin" SPARKLE_PRIVATE_ED_KEY=test \
    "$generator" v1.2.0 update.zip >/dev/null 2>&1; then
    echo "expected invalid origin '$origin' to fail" >&2
    exit 1
  fi
done

printf sentinel > target.xml
ln -s target.xml appcast.xml
if env SPARKLE_PRIVATE_ED_KEY=test "$generator" v1.2.0 update.zip >/dev/null 2>&1; then
  echo "expected a symlink appcast output to fail" >&2
  exit 1
fi
grep -Fqx sentinel target.xml

echo "Appcast validation tests passed."
