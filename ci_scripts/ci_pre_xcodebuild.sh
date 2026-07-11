#!/bin/sh

# Xcode Cloud runs this right before each xcodebuild action (build / test /
# archive). Xcode Cloud doesn't expose the scheme in this phase for every
# command it runs, so the hard Sparkle check lives in ci_post_xcodebuild.sh.
# If the scheme is available here, fail early for clearly wrong archives.
#
# Both the Developer ID and App Store targets produce PadBuddy.app. If Xcode
# Cloud reuses build products, a Sparkle.framework copied by the Developer ID
# target can remain in that app bundle even when the App Store target doesn't
# link Sparkle. Remove stale Sparkle copies before archiving.

set -e

action="${CI_XCODEBUILD_ACTION:-}"
scheme="${CI_XCODEBUILD_SCHEME:-${CI_SCHEME:-}}"

if [ "$action" = "archive" ] && [ -n "$scheme" ] && [ "$scheme" != "CoderPad-AppStore" ]; then
  echo "error: Xcode Cloud archive is using scheme '${scheme:-unknown}'."
  echo "Use the CoderPad-AppStore scheme for App Store Connect uploads; the coderpad scheme embeds Sparkle."
  exit 1
fi

if [ "$action" = "archive" ]; then
  workspace="${CI_WORKSPACE:-}"
  if [ -z "$workspace" ] && [ -n "${CI_PRIMARY_REPOSITORY_PATH:-}" ]; then
    workspace="$(dirname "$CI_PRIMARY_REPOSITORY_PATH")"
  fi

  if [ -n "$workspace" ] && [ -d "$workspace" ]; then
    find "$workspace" \
      -path '*/PadBuddy.app/Contents/Frameworks/Sparkle.framework' \
      -prune \
      -exec rm -rf {} +
  fi
fi

echo "ci_pre_xcodebuild: OK for action='${action:-unknown}' scheme='${scheme:-unknown}'."
