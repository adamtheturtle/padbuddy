#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$repo_root/scripts/check-privacy-manifests.sh"
fixture="$(mktemp -d)"
case_root="$fixture/case"
trap 'rm -rf "$fixture"' EXIT

reset_fixture() {
  rm -rf "$case_root"
  mkdir -p "$case_root/coderpad.xcodeproj"
  cp -R "$repo_root/coderpad" "$repo_root/RecentPadsWidget" "$repo_root/WatchApp" "$case_root/"
  cp "$repo_root/coderpad.xcodeproj/project.pbxproj" "$case_root/coderpad.xcodeproj/"
}

assert_rejected() {
  if PRIVACY_ROOT="$case_root" "$gate" >/dev/null 2>&1; then
    echo "expected invalid privacy fixture to fail: $1" >&2
    exit 1
  fi
}

reset_fixture
/usr/libexec/PlistBuddy -c 'Delete :NSPrivacyAccessedAPITypes:0' "$case_root/coderpad/PrivacyInfo.xcprivacy"
assert_rejected 'missing app UserDefaults reason'

reset_fixture
/usr/libexec/PlistBuddy -c 'Delete :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPITypeReasons' \
  -c 'Add :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPITypeReasons string C617.1' \
  "$case_root/coderpad/PrivacyInfo.xcprivacy"
assert_rejected 'scalar reason field'

reset_fixture
/usr/libexec/PlistBuddy -c 'Set :NSPrivacyTracking true' "$case_root/coderpad/PrivacyInfo.xcprivacy"
assert_rejected 'tracking enabled'

reset_fixture
/usr/libexec/PlistBuddy -c 'Add :NSPrivacyCollectedDataTypes:0 dict' "$case_root/coderpad/PrivacyInfo.xcprivacy"
assert_rejected 'collected data declaration'

reset_fixture
sed '/66C8C50D2FA73AB0009B720C \/\* coderpad \*\//d' \
  "$case_root/coderpad.xcodeproj/project.pbxproj" > "$case_root/project.tmp"
mv "$case_root/project.tmp" "$case_root/coderpad.xcodeproj/project.pbxproj"
assert_rejected 'missing synchronized target membership'

echo "Privacy manifest adversarial tests passed."
