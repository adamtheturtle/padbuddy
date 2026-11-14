#!/usr/bin/env bash
#
# One-command local confidence check before pushing a branch.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
architecture="$(uname -m)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
result_root="${PREFLIGHT_RESULT_ROOT:-$repo_root/.context/preflight/$run_id}"
derived_data="${PREFLIGHT_DERIVED_DATA_PATH:-$repo_root/.context/DerivedData-preflight}"
parallel_workers="${PREFLIGHT_TEST_WORKERS:-2}"

for command_name in git jq swiftformat swiftlint xcodebuild; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: preflight requires $command_name on PATH" >&2
    exit 69
  fi
done

# Keep the last N runs of result bundles. An `.xcresult` for a full build plus a test plan
# runs to hundreds of megabytes, `run_id` is fresh on every invocation, and nothing ever
# deleted them — so running this a few times a day silently accumulated tens of gigabytes
# under a gitignored directory nothing surfaces (issue #4764).
prune_result_bundles() {
  local directory="$1" keep="${2:-5}"
  [ -d "$directory" ] || return 0

  local entries=()
  while IFS= read -r entry; do
    [ -n "$entry" ] && entries+=("$entry")
  done < <(find "$directory" -mindepth 1 -maxdepth 1 -print 2>/dev/null | sort)
  local excess=$(( ${#entries[@]} - keep ))
  [ "$excess" -gt 0 ] || return 0

  local index=0
  for entry in "${entries[@]}"; do
    [ "$index" -lt "$excess" ] || break
    rm -rf -- "$entry"
    index=$(( index + 1 ))
  done
  echo "Pruned $excess older result bundle(s) from $directory"
}

mkdir -p "$result_root"
# Names sort by the UTC timestamp in `run_id`, so the oldest are the ones pruned.
prune_result_bundles "$(dirname "$result_root")" "${PREFLIGHT_KEEP_RESULTS:-5}"
cd "$repo_root"

echo "==> Resolving pinned Swift packages"
xcodebuild -resolvePackageDependencies \
  -quiet \
  -project PadBuddy.xcodeproj \
  -scheme PadBuddy \
  -onlyUsePackageVersionsFromResolvedFile

echo "==> Running SwiftLint"
swiftlint lint --strict --quiet

echo "==> Checking SwiftFormat"
swiftformat . --lint

echo "==> Checking appcast input and resolved tooling validation"
scripts/test-generate-appcast-validation.sh

echo "==> Building the macOS app"
scripts/run-xcodebuild.sh "$result_root/Build.log" build \
  -quiet \
  -showBuildTimingSummary \
  -project PadBuddy.xcodeproj \
  -scheme PadBuddy \
  -configuration Debug \
  -destination "platform=macOS,arch=$architecture" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$result_root/Build.xcresult" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

echo "==> Running the Fast test plan"
scripts/run-xcodebuild.sh "$result_root/FastTests.log" test \
  -quiet \
  -showBuildTimingSummary \
  -project PadBuddy.xcodeproj \
  -scheme PadBuddy \
  -testPlan Fast \
  -destination "platform=macOS,arch=$architecture" \
  -derivedDataPath "$derived_data" \
  -resultBundlePath "$result_root/FastTests.xcresult" \
  -parallel-testing-worker-count "$parallel_workers" \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

echo "==> Checking patches for whitespace errors"
git diff --check
git diff --cached --check

echo "Preflight passed. Result bundles: $result_root"
