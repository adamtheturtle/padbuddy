#!/usr/bin/env bash
#
# bump-version.sh — set the marketing version and build number across every
# build configuration in the Xcode project, in one step, so an upload never
# ships with a stale or mismatched version (issue #48).
#
# Usage:
#   scripts/bump-version.sh <marketing-version> [build-number]
#
#   <marketing-version>  The user-facing version, e.g. 1.2 or 1.2.0 (CFBundleShortVersionString).
#   [build-number]       The build (CFBundleVersion). Optional; defaults to the
#                        current highest build number plus one.
#
# Examples:
#   scripts/bump-version.sh 1.3.0        # marketing 1.3.0, build auto-incremented
#   scripts/bump-version.sh 1.3.0 47     # marketing 1.3.0, build pinned to 47
#
# The script edits MARKETING_VERSION and CURRENT_PROJECT_VERSION in the
# project file and verifies every occurrence ended up consistent. It does not
# commit or tag — review the diff, then commit (see RELEASING.md).

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pbxproj="$repo_root/coderpad.xcodeproj/project.pbxproj"

if [[ ! -f "$pbxproj" ]]; then
  echo "error: project file not found at $pbxproj" >&2
  exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $(basename "$0") <marketing-version> [build-number]" >&2
  exit 64
fi

marketing="$1"

# Accept X.Y or X.Y.Z (App Store rejects anything else for CFBundleShortVersionString).
if [[ ! "$marketing" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  echo "error: marketing version '$marketing' must look like 1.2 or 1.2.0" >&2
  exit 64
fi

# Resolve the build number: explicit argument, or current highest + 1.
if [[ $# -eq 2 ]]; then
  build="$2"
  if [[ ! "$build" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: build number '$build' must be a positive integer" >&2
    exit 64
  fi
else
  current_max="$(grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' "$pbxproj" \
    | grep -Eo '[0-9]+' | sort -n | tail -1)"
  current_max="${current_max:-0}"
  build=$(( current_max + 1 ))
fi

echo "Setting MARKETING_VERSION    -> $marketing"
echo "Setting CURRENT_PROJECT_VERSION -> $build"

# Rewrite via a temp file so this works identically under BSD (macOS) and GNU
# sed — no reliance on the incompatible -i flag.
tmp="$(mktemp)"
sed -E \
  -e "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${marketing};/g" \
  -e "s/CURRENT_PROJECT_VERSION = [^;]+;/CURRENT_PROJECT_VERSION = ${build};/g" \
  "$pbxproj" > "$tmp"
mv "$tmp" "$pbxproj"

# Verify every configuration now agrees, so a missed target can't ship a split version.
stray_marketing="$(grep -Eo 'MARKETING_VERSION = [^;]+;' "$pbxproj" | grep -v "= ${marketing};" || true)"
stray_build="$(grep -Eo 'CURRENT_PROJECT_VERSION = [^;]+;' "$pbxproj" | grep -v "= ${build};" || true)"
if [[ -n "$stray_marketing" || -n "$stray_build" ]]; then
  echo "error: not all configurations updated consistently:" >&2
  [[ -n "$stray_marketing" ]] && echo "$stray_marketing" >&2
  [[ -n "$stray_build" ]] && echo "$stray_build" >&2
  exit 1
fi

marketing_count="$(grep -c 'MARKETING_VERSION = ' "$pbxproj")"
build_count="$(grep -c 'CURRENT_PROJECT_VERSION = ' "$pbxproj")"
echo "Updated $marketing_count MARKETING_VERSION and $build_count CURRENT_PROJECT_VERSION entries."
echo "Review the diff, then commit. See RELEASING.md."
