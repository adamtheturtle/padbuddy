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

cd "$repo_root"
mkdir -p "$(dirname "$result_bundle")"

exec scripts/run-xcodebuild.sh "$build_log" build \
  -quiet \
  -showBuildTimingSummary \
  -project coderpad.xcodeproj \
  -scheme coderpad \
  -configuration Debug \
  -destination "platform=macOS,arch=$architecture" \
  -resultBundlePath "$result_bundle" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  LM_SKIP_METADATA_EXTRACTION=YES \
  ENABLE_CODE_COVERAGE=NO \
  "$@"
