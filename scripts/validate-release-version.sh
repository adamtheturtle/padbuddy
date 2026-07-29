#!/usr/bin/env bash
#
# Validate release upload version inputs before an archive is built or published.
# Usage: scripts/validate-release-version.sh <marketing-version> <build-number> [tag-name]

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $(basename "$0") <marketing-version> <build-number> [tag-name]" >&2
  exit 64
fi

marketing="$1"
build="$2"
tag="${3:-}"
if [[ "$tag" == appstore-v* ]]; then
  channel_prefix="appstore-v"
else
  channel_prefix="v"
fi

if [[ ! "$marketing" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: marketing version '$marketing' must look like 1.2 or 1.2.0" >&2
  exit 64
fi

if [[ ! "$build" =~ ^[0-9]+$ || "$build" == "0" ]]; then
  echo "error: build number '$build' must be a positive integer" >&2
  exit 64
fi

server_version="$(sed -nE 's/.*padBuddyReleaseVersion = "([^"]+)".*/\1/p' \
  CoderPadMCP/Sources/CoderPadMCPCore/ReleaseVersion.swift)"
if [[ "$server_version" != "$marketing" ]]; then
  echo "error: standalone MCP version '$server_version' does not match '$marketing'" >&2
  exit 1
fi

if [[ -n "$tag" ]]; then
  tag_version="$tag"
  tag_version="${tag_version#appstore-v}"
  tag_version="${tag_version#v}"
  if [[ "$tag_version" != "$marketing" ]]; then
    echo "error: tag '$tag' resolves to marketing version '$tag_version', not '$marketing'" >&2
    exit 64
  fi
fi

max_prior_build=0
duplicate_tags=()
while IFS= read -r existing_tag; do
  [[ -n "$existing_tag" ]] || continue
  [[ "$existing_tag" == "$tag" ]] && continue

  existing_version="$existing_tag"
  existing_version="${existing_version#appstore-v}"
  existing_version="${existing_version#v}"
  if [[ "$existing_tag" == "$channel_prefix"* && "$existing_version" == "$marketing" ]]; then
    duplicate_tags+=("$existing_tag")
  fi

  existing_build="$(git rev-list --count "$existing_tag^{commit}")"
  if (( existing_build > max_prior_build )); then
    max_prior_build="$existing_build"
  fi
done < <(git tag --list 'v*' && git tag --list 'appstore-v*')

if (( ${#duplicate_tags[@]} > 0 )); then
  echo "error: marketing version '$marketing' is already used by tag(s): ${duplicate_tags[*]}" >&2
  exit 1
fi

if (( build <= max_prior_build )); then
  echo "error: build number '$build' must be greater than prior upload build '$max_prior_build'" >&2
  exit 1
fi

echo "Validated release version $marketing (build $build)."
