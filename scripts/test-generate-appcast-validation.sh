#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generator="$repo_root/scripts/generate-appcast.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
cd "$fixture"
unset SPARKLE_VERSION
printf archive > update.zip
printf archive > padbuddy-v1.2.0.zip
resolved_path="PadBuddy.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$resolved_path")"
cp "$repo_root/$resolved_path" "$resolved_path"

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

# A supported resolved version must reach the download step. This catches a
# package upgrade whose trusted tool archive checksum has not been pinned yet.
mkdir bin
cat > bin/curl <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_CURL_LOG"
exit 73
CURL
chmod +x bin/curl
if env PATH="$fixture/bin:$PATH" TEST_CURL_LOG="$fixture/curl.log" \
  SPARKLE_PRIVATE_ED_KEY=test "$generator" v1.2.0 padbuddy-v1.2.0.zip \
  > generator.log 2>&1; then
  echo "expected the download stub to stop appcast generation" >&2
  exit 1
fi
resolved_version="$(jq -er '.pins[] | select(.identity == "sparkle") | .state.version' "$resolved_path")"
grep -Fqx "https://github.com/sparkle-project/Sparkle/releases/download/$resolved_version/Sparkle-$resolved_version.tar.xz" curl.log

echo "Appcast validation tests passed."
