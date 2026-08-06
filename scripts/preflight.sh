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

for command_name in git swiftformat swiftlint xcodebuild; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: preflight requires $command_name on PATH" >&2
    exit 69
  fi
done

mkdir -p "$result_root"
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
