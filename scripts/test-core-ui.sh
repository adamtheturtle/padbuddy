#!/usr/bin/env bash
# Keep XCUITest's launch/termination lifecycle separate from personal PadBuddy.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
"${XCODEBUILD_BIN:-xcodebuild}" test -quiet \
  -project PadBuddy.xcodeproj -scheme PadBuddy -testPlan CoreUI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "${CORE_UI_DERIVED_DATA_PATH:-$repo_root/.context/DerivedData-core-ui}" \
  -only-testing:PadBuddyUITests/CoderpadAccountBrowserUITests \
  -only-testing:PadBuddyUITests/CoderpadUITests/testSectionNavigationFlow \
  "$@" PADBUDDY_TEST_BUNDLE_SUFFIX=.uitesting
