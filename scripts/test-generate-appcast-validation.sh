#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generator="$repo_root/scripts/generate-appcast.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
printf archive > update.zip
printf archive > padbuddy-v1.2.0.zip

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

rm -f appcast.xml

# The archive basename becomes the last path component of the signed enclosure URL
# (issue #4583).
for name in 'update.zip' 'padbuddy-v1.2.0 copy.zip' 'padbuddy-v1.2.0.zip?x' \
  'padbuddy-v1.2.0.tar.gz' 'padbuddy-v1.3.0.zip'; do
  printf archive > "$name"
  if env SPARKLE_PRIVATE_ED_KEY=test "$generator" v1.2.0 "$name" >/dev/null 2>&1; then
    echo "expected archive name '$name' to fail" >&2
    exit 1
  fi
  rm -f "$name"
done

# A RELEASES_REPOSITORY typo must not produce a signed feed pointing elsewhere
# (issue #4584).
for repository in 'owner' 'owner/repo/extra' 'owner/../repo' 'owner /repo' \
  'owner/repo?x' 'owner/repo#x' '/repo' 'owner/'; do
  if env SPARKLE_PRIVATE_ED_KEY=test RELEASES_REPOSITORY="$repository" \
    "$generator" v1.2.0 padbuddy-v1.2.0.zip >/dev/null 2>&1; then
    echo "expected RELEASES_REPOSITORY '$repository' to fail" >&2
    exit 1
  fi
done

echo "Appcast validation tests passed."
