#!/bin/sh

# Xcode Cloud runs this right before each xcodebuild action (build / test /
# archive). App Store Connect archives must use the Sparkle-free App Store
# target; the regular coderpad target intentionally embeds Sparkle for direct
# Developer ID updates and App Store Connect rejects it.

set -e

action="${CI_XCODEBUILD_ACTION:-}"
scheme="${CI_XCODEBUILD_SCHEME:-${CI_SCHEME:-}}"

if [ "$action" = "archive" ] && [ "$scheme" != "CoderPad-AppStore" ]; then
  echo "error: Xcode Cloud archive is using scheme '${scheme:-unknown}'."
  echo "Use the CoderPad-AppStore scheme for App Store Connect uploads; the coderpad scheme embeds Sparkle."
  exit 1
fi

echo "ci_pre_xcodebuild: OK for action='${action:-unknown}' scheme='${scheme:-unknown}'."
