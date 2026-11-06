#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$repo_root/scripts/check-privacy-manifests.sh"
fixture="$(mktemp -d)"
case_root="$fixture/case"
trap 'rm -rf "$fixture"' EXIT

reset_fixture() {
  rm -rf "$case_root"
  mkdir -p "$case_root/PadBuddy.xcodeproj"
  cp -R "$repo_root/PadBuddy" "$repo_root/RecentPadsWidget" "$repo_root/WatchApp" "$case_root/"
  cp "$repo_root/PadBuddy.xcodeproj/project.xcproj" "$case_root/PadBuddy.xcodeproj/"
}

assert_rejected() {
  if PRIVACY_ROOT="$case_root" "$gate" >/dev/null 2>&1; then
    echo "expected invalid privacy fixture to fail: $1" >&2
    exit 1
  fi
}

reset_fixture
/usr/libexec/PlistBuddy -c 'Delete :NSPrivacyAccessedAPITypes:0' "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'missing app UserDefaults reason'

reset_fixture
/usr/libexec/PlistBuddy -c 'Delete :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPITypeReasons' \
  -c 'Add :NSPrivacyAccessedAPITypes:1:NSPrivacyAccessedAPITypeReasons string C617.1' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'scalar reason field'

reset_fixture
/usr/libexec/PlistBuddy -c 'Set :NSPrivacyTracking true' "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'tracking enabled'

reset_fixture
/usr/libexec/PlistBuddy -c 'Add :NSPrivacyCollectedDataTypes:0 dict' "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'collected data declaration'

reset_fixture
sed '/^[[:space:]]*"PadBuddy",$/d' \
  "$case_root/PadBuddy.xcodeproj/project.xcproj" > "$case_root/project.tmp"
mv "$case_root/project.tmp" "$case_root/PadBuddy.xcodeproj/project.xcproj"
assert_rejected 'missing synchronized target membership'

reset_fixture
sed 's@PadBuddy Watch App/resources@PadBuddy/resources@g' \
  "$case_root/PadBuddy.xcodeproj/project.xcproj" > "$case_root/project.tmp"
mv "$case_root/project.tmp" "$case_root/PadBuddy.xcodeproj/project.xcproj"
assert_rejected 'watch manifest attached to the wrong target'

reset_fixture
sed 's/"Info.plist",/"Info.plist", "PrivacyInfo.xcprivacy",/' \
  "$case_root/PadBuddy.xcodeproj/project.xcproj" > "$case_root/project.tmp"
mv "$case_root/project.tmp" "$case_root/PadBuddy.xcodeproj/project.xcproj"
assert_rejected 'privacy manifest excluded from synchronized membership'

reset_fixture
/usr/libexec/PlistBuddy -c 'Add :NSPrivacyTrackingDomains:0 integer 5' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'non-string tracking domain'

reset_fixture
/usr/libexec/PlistBuddy -c 'Add :NSPrivacyTrackingDomains:0 string ""' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'empty tracking domain'

reset_fixture
/usr/libexec/PlistBuddy -c 'Add :NSPrivacyTrackingDomains:0 string "not a domain"' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'malformed tracking domain'

reset_fixture
/usr/libexec/PlistBuddy -c 'Add :NSPrivacyTrackingDomains:0 string "ads.example.com"' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'tracking domain declared while tracking is false'

reset_fixture
/usr/libexec/PlistBuddy \
  -c 'Set :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPIType NSPrivacyAccessedAPICategoryTypo' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'unreviewed API category'

reset_fixture
/usr/libexec/PlistBuddy -c 'Set :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0 CA92.9' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'unreviewed reason code'

reset_fixture
/usr/libexec/PlistBuddy -c 'Delete :NSPrivacyAccessedAPITypes:0:NSPrivacyAccessedAPITypeReasons:0' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'empty reason list'

reset_fixture
/usr/libexec/PlistBuddy \
  -c 'Add :NSPrivacyAccessedAPITypes:2 dict' \
  -c 'Add :NSPrivacyAccessedAPITypes:2:NSPrivacyAccessedAPIType string NSPrivacyAccessedAPICategoryUserDefaults' \
  -c 'Add :NSPrivacyAccessedAPITypes:2:NSPrivacyAccessedAPITypeReasons array' \
  -c 'Add :NSPrivacyAccessedAPITypes:2:NSPrivacyAccessedAPITypeReasons:0 string CA92.1' \
  "$case_root/PadBuddy/PrivacyInfo.xcprivacy"
assert_rejected 'duplicate API category entry'

echo "Privacy manifest adversarial tests passed."
