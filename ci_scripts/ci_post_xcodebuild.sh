#!/bin/sh

# Xcode Cloud runs this after each xcodebuild action. Xcode Cloud is only used
# for App Store Connect distribution in this repo; Developer ID releases are
# packaged outside Xcode Cloud. Fail before upload if an archive contains
# Sparkle, whose nested executables are rejected by App Store Connect. Managed
# distribution signing is applied to the exported product, so the archive
# intermediate inspected here may legitimately retain an ad-hoc signature.

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
  archive_platform="macOS"
else
  info_plist="$app/Info.plist"
  frameworks_dir="$app/Frameworks"
  plugins_dir="$app/PlugIns"
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

echo "ci_post_xcodebuild: OK, $archive_platform archive is Sparkle-free and structurally valid."
