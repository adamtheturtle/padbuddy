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

if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
  echo "ci_post_xcodebuild: no archive to inspect."
  exit 0
fi

applications_dir="$CI_ARCHIVE_PATH/Products/Applications"
if [ ! -d "$applications_dir" ]; then
  echo "ci_post_xcodebuild: archive applications directory not found at $applications_dir."
  exit 0
fi

app="$(find "$applications_dir" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$app" ]; then
  echo "ci_post_xcodebuild: archived app not found under $CI_ARCHIVE_PATH."
  exit 1
fi

workflow="${CI_WORKFLOW:-}"
scheme="${CI_XCODEBUILD_SCHEME:-${CI_SCHEME:-}}"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"

if [ -e "$app/Contents/Frameworks/Sparkle.framework" ]; then
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

verify_hardened_runtime "$app" "the app"
find "$app/Contents/PlugIns" -type d -name '*.appex' -print 2>/dev/null | while IFS= read -r extension; do
  verify_hardened_runtime "$extension" "$(basename "$extension")"
done

echo "ci_post_xcodebuild: OK, archive is Sparkle-free and Hardened Runtime is enabled."
