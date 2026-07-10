#!/bin/sh

# Xcode Cloud runs this after each xcodebuild action. For archive actions, fail
# before upload if the App Store archive contains Sparkle. The Developer ID
# target intentionally links Sparkle for direct updates, but App Store Connect
# rejects those nested Sparkle executables.

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

if [ -e "$app/Contents/Frameworks/Sparkle.framework" ]; then
  echo "error: Sparkle.framework is embedded in this archive."
  echo "Use the CoderPad-AppStore scheme/target for App Store Connect uploads."
  exit 1
fi

echo "ci_post_xcodebuild: OK, archive is Sparkle-free."
