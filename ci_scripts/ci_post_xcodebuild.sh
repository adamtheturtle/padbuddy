#!/bin/sh

# Xcode Cloud runs this after each xcodebuild action. Xcode Cloud is only used
# for App Store Connect distribution in this repo; Developer ID releases are
# packaged outside Xcode Cloud. Fail before upload if an archive contains
# Sparkle, whose nested executables are rejected by App Store Connect.

set -e

if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
  echo "ci_post_xcodebuild: no archive to inspect."
  exit 0
fi

app="$(find "$CI_ARCHIVE_PATH/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
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

echo "ci_post_xcodebuild: OK, archive is Sparkle-free."
