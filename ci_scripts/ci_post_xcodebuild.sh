#!/bin/sh

# Xcode Cloud runs this after each xcodebuild action. For archive actions that
# are meant for App Store Connect, fail before upload if the archive contains
# Sparkle. The Developer ID target intentionally links Sparkle for direct
# updates, so non-App-Store workflows are allowed to archive it.

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

requires_sparkle_free_archive=0
case "${CI_REQUIRE_SPARKLE_FREE_ARCHIVE:-}" in
  1|[Tt][Rr][Uu][Ee]|[Yy][Ee][Ss])
    requires_sparkle_free_archive=1
    ;;
esac

case "$workflow $scheme" in
  *AppStore*|*"App Store"*|*TestFlight*|*"Store Connect"*|*ASC*|*CoderPad-AppStore*)
    requires_sparkle_free_archive=1
    ;;
esac

if [ -e "$app/Contents/Frameworks/Sparkle.framework" ]; then
  if [ "$requires_sparkle_free_archive" -ne 1 ]; then
    echo "ci_post_xcodebuild: Sparkle archive allowed for non-App-Store workflow."
    echo "ci_post_xcodebuild: workflow='${workflow:-unknown}' scheme='${scheme:-unknown}' bundle='${bundle_id:-unknown}'."
    exit 0
  fi

  echo "error: Sparkle.framework is embedded in this archive."
  echo "Use the CoderPad-AppStore scheme/target for App Store Connect uploads."
  echo "ci_post_xcodebuild: workflow='${workflow:-unknown}' scheme='${scheme:-unknown}' bundle='${bundle_id:-unknown}'."
  echo "ci_post_xcodebuild: archive='$CI_ARCHIVE_PATH'."
  exit 1
fi

echo "ci_post_xcodebuild: OK, archive is Sparkle-free."
