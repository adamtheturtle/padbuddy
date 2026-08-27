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

# One canonical component rule, matching bump-version.sh: no leading zeros, and short
# enough for the fixed-width comparison both scripts rely on. The looser `[0-9]+` here
# accepted `01.002` and components far longer than nine digits, so the two release gates
# disagreed about what a valid version was (issue #4582).
component='(0|[1-9][0-9]{0,8})'
version_pattern="^${component}\.${component}(\.${component})?$"

if [[ ! "$marketing" =~ $version_pattern ]]; then
  echo "error: marketing version '$marketing' must look like 1.2 or 1.2.0" >&2
  exit 64
fi

# The channel is decided by the tag's full form, not by a prefix that may not be there.
# Stripping optional prefixes without ever requiring one meant a bare `1.2` validated as a
# release tag the workflows would not classify the same way (issue #4581).
if [[ -n "$tag" ]]; then
  if [[ "$tag" =~ ^appstore-v${component}\.${component}(\.${component})?$ ]]; then
    channel_prefix="appstore-v"
  elif [[ "$tag" =~ ^v${component}\.${component}(\.${component})?$ ]]; then
    channel_prefix="v"
  else
    echo "error: tag '$tag' must look like v1.2.0 or appstore-v1.2.0" >&2
    exit 64
  fi
else
  channel_prefix="v"
fi

max_build=2147483647
if [[ ! "$build" =~ ^[1-9][0-9]*$ || ${#build} -gt 10 ]]; then
  echo "error: build number '$build' must be a positive integer" >&2
  exit 64
fi
build_number=$((10#$build))
if (( build_number > max_build )); then
  echo "error: build number '$build' must be $max_build or less" >&2
  exit 64
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
if ! existing_tags="$(git tag --list 'v*' && git tag --list 'appstore-v*')"; then
  echo "error: could not enumerate existing release tags" >&2
  exit 1
fi
while IFS= read -r existing_tag; do
  [[ -n "$existing_tag" ]] || continue
  [[ "$existing_tag" == "$tag" ]] && continue

  existing_version="$existing_tag"
  existing_version="${existing_version#appstore-v}"
  existing_version="${existing_version#v}"
  if [[ "$existing_tag" == "$channel_prefix"* && "$existing_version" == "$marketing" ]]; then
    duplicate_tags+=("$existing_tag")
  fi

  if ! existing_project="$(git show "$existing_tag^{commit}:PadBuddy.xcodeproj/project.pbxproj")"; then
    echo "error: could not read the project version at '$existing_tag'" >&2
    exit 1
  fi
  existing_build="$(printf '%s\n' "$existing_project" \
    | grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' \
    | grep -Eo '[0-9]+' | sort -n | tail -1)"
  if [[ ! "$existing_build" =~ ^[1-9][0-9]*$ || ${#existing_build} -gt 10 ]]; then
    echo "error: '$existing_tag' has no valid CURRENT_PROJECT_VERSION" >&2
    exit 1
  fi
  existing_build=$((10#$existing_build))
  if (( existing_build > max_prior_build )); then
    max_prior_build="$existing_build"
  fi
done <<< "$existing_tags"

if (( ${#duplicate_tags[@]} > 0 )); then
  echo "error: marketing version '$marketing' is already used by tag(s): ${duplicate_tags[*]}" >&2
  exit 1
fi

if (( build_number <= max_prior_build )); then
  echo "error: build number '$build' must be greater than prior upload build '$max_prior_build'" >&2
  exit 1
fi

echo "Validated release version $marketing (build $build)."
