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

cd "$repo_root"

exec xcodebuild build \
  -project coderpad.xcodeproj \
  -scheme coderpad \
  -configuration Debug \
  -destination "platform=macOS,arch=$architecture" \
  -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile \
  LM_SKIP_METADATA_EXTRACTION=YES \
  ENABLE_CODE_COVERAGE=NO \
  "$@"
