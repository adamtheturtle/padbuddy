#!/bin/sh

# Xcode Cloud runs this after each xcodebuild action. Xcode Cloud is only used
# for App Store Connect distribution in this repo; Developer ID releases are
# packaged outside Xcode Cloud. Fail before upload if an archive contains
# Sparkle, whose nested executables are rejected by App Store Connect.

set -e

if [ "${CI_XCODEBUILD_EXIT_CODE:-0}" != "0" ]; then
  echo "ci_post_xcodebuild: xcodebuild exited with ${CI_XCODEBUILD_EXIT_CODE}; skipping archive inspection."
  exit 0
fi

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  echo "ci_post_xcodebuild: action is '${CI_XCODEBUILD_ACTION:-unknown}', no archive inspection required."
  exit 0
fi

if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
  echo "error: archive action completed without CI_ARCHIVE_PATH."
  exit 1
fi

applications_dir="$CI_ARCHIVE_PATH/Products/Applications"
if [ ! -d "$applications_dir" ]; then
  echo "error: archive applications directory not found at $applications_dir."
  exit 1
fi

app_count="$(find "$applications_dir" -maxdepth 1 -type d -name '*.app' -print | wc -l | tr -d ' ')"
if [ "$app_count" -ne 1 ]; then
  echo "error: expected exactly one archived app under $applications_dir; found $app_count."
  exit 1
fi
app="$(find "$applications_dir" -maxdepth 1 -type d -name '*.app' -print -quit)"

workflow="${CI_WORKFLOW:-}"
scheme="${CI_XCODEBUILD_SCHEME:-${CI_SCHEME:-}}"
if [ -f "$app/Contents/Info.plist" ]; then
  info_plist="$app/Contents/Info.plist"
  frameworks_dir="$app/Contents/Frameworks"
  plugins_dir="$app/Contents/PlugIns"
  provisioning_profile="$app/Contents/embedded.provisionprofile"
  archive_platform="macOS"
else
  info_plist="$app/Info.plist"
  frameworks_dir="$app/Frameworks"
  plugins_dir="$app/PlugIns"
  provisioning_profile="$app/embedded.mobileprovision"
  archive_platform="iOS"
fi
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist" 2>/dev/null || true)"

if [ "$bundle_id" != "com.adamdangoor.padbuddy" ]; then
  echo "error: expected app bundle identifier com.adamdangoor.padbuddy; found ${bundle_id:-unknown}."
  exit 1
fi

if [ -e "$frameworks_dir/Sparkle.framework" ]; then
  echo "error: Sparkle.framework is embedded in this archive."
  echo "Use the CoderPad-AppStore scheme/target for App Store Connect uploads."
  echo "ci_post_xcodebuild: workflow='${workflow:-unknown}' scheme='${scheme:-unknown}' bundle='${bundle_id:-unknown}'."
  echo "ci_post_xcodebuild: archive='$CI_ARCHIVE_PATH'."
  exit 1
fi

expected_team="6L9H6Q8CUF"
signature_details="$(codesign --display --verbose=4 "$app" 2>&1)" || {
  echo "error: Could not inspect the archive signature."
  echo "$signature_details"
  exit 1
}
team="$(echo "$signature_details" | awk -F= '/^TeamIdentifier=/{ print $2; exit }')"
authority="$(echo "$signature_details" | awk -F= '/^Authority=/{ print $2; exit }')"
if [ "$team" != "$expected_team" ] || [ -z "$authority" ] || [ "$authority" = "adhoc" ]; then
  echo "error: archive is not signed by paid Apple Developer team $expected_team."
  echo "ci_post_xcodebuild: team='${team:-missing}' authority='${authority:-missing}'."
  exit 1
fi

if [ ! -f "$provisioning_profile" ]; then
  echo "error: $archive_platform archive has no embedded provisioning profile."
  exit 1
fi
profile_plist="$(mktemp)"
trap 'rm -f "$profile_plist"' EXIT
security cms -D -i "$provisioning_profile" > "$profile_plist"
profile_team="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_plist" 2>/dev/null || true)"
profile_expiration="$(/usr/libexec/PlistBuddy -c 'Print :ExpirationDate' "$profile_plist" 2>/dev/null || true)"
if [ "$profile_team" != "$expected_team" ] || [ -z "$profile_expiration" ]; then
  echo "error: embedded provisioning profile is not valid for team $expected_team."
  echo "ci_post_xcodebuild: profile team='${profile_team:-missing}' expiration='${profile_expiration:-missing}'."
  exit 1
fi
echo "ci_post_xcodebuild: paid-team signature and provisioning profile verified for $archive_platform."

verify_hardened_runtime() {
  executable="$1"
  label="$2"
  details="$(codesign --display --verbose=4 "$executable" 2>&1)" || {
    echo "error: Could not inspect the signature for $label."
    echo "$details"
    exit 1
  }
  if ! echo "$details" | grep -Eq 'flags=.*\(.*runtime.*\)'; then
    echo "error: $label is signed without Hardened Runtime."
    echo "$details"
    exit 1
  fi
  echo "ci_post_xcodebuild: Hardened Runtime verified for $label."
}

if [ "$archive_platform" = "macOS" ]; then
  verify_hardened_runtime "$app" "the app"
  find "$plugins_dir" -type d -name '*.appex' -print 2>/dev/null | while IFS= read -r extension; do
    verify_hardened_runtime "$extension" "$(basename "$extension")"
  done
fi

echo "ci_post_xcodebuild: OK, archive is Sparkle-free and paid-team provisioning is valid."
