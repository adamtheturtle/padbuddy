#!/usr/bin/env bash
#
# Fast local Debug build. This keeps the normal project, test, archive, and
# release settings authoritative while removing work that is unnecessary for
# most edit/build/run loops.
#
# Use a normal Xcode build after changing App Intents or widget configuration:
# this command deliberately skips their metadata extraction.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
architecture="$(uname -m)"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
result_bundle="${BUILD_FAST_RESULT_BUNDLE_PATH:-$repo_root/.context/build-fast/$run_id.xcresult}"
build_log="${BUILD_FAST_LOG_PATH:-$repo_root/.context/build-fast/$run_id.log}"

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

cd "$repo_root"
mkdir -p "$(dirname "$result_bundle")"
# Names sort by the UTC timestamp in `run_id`, so the oldest are the ones pruned. Each
# run leaves an `.xcresult` and a `.log`, so the count is doubled (issue #4764).
prune_result_bundles "$(dirname "$result_bundle")" "$(( ${BUILD_FAST_KEEP_RESULTS:-10} * 2 ))"

exec scripts/run-xcodebuild.sh "$build_log" build \
  -quiet \
  -showBuildTimingSummary \
  -project PadBuddy.xcodeproj \
  -scheme PadBuddy \
  -configuration Debug \
  -destination "platform=macOS,arch=$architecture" \
  -resultBundlePath "$result_bundle" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  LM_SKIP_METADATA_EXTRACTION=YES \
  ENABLE_CODE_COVERAGE=NO \
  "$@"
