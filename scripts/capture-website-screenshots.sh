#!/usr/bin/env bash
#
# Regenerate the in-app marketing screenshots for the website (docs/) and the
# App Store listing, end to end. It drives the seeded, PII-free `-uiTesting`
# demo account through a few representative states via the
# dedicated `testCaptureWebsiteHeroLightDark` UI test, then extracts the PNGs.
#
# Why a script: capturing these by hand is a fiddly multi-step dance (documented
# the hard way across #505/#506/#62) —
#   1. the test runner is sandboxed, so it can only emit screenshots as
#      XCTAttachments, not files on disk;
#   2. a *passing* test's attachments are stripped unless the test plan opts in
#      with `userAttachmentLifetime = keepAlways`;
#   3. the attachments only survive in the *finalized* .xcresult, and must be
#      pulled out with `xcresulttool export attachments`.
# This script does all three (toggling the plan option and reverting it after),
# so refreshing the shots is one command.
#
# Usage:
#   scripts/capture-website-screenshots.sh                 # capture, export to a staging dir, print a mapping
#   scripts/capture-website-screenshots.sh --install       # ...and also copy/resize them into docs/assets/
#   scripts/capture-website-screenshots.sh --export-only <result.xcresult> [--install]
#                                                          # skip the capture; just export from an existing bundle
#
# Notes:
#   * Run on a FREE GUI session. If another process is driving the app, capture
#     fails with "Failed to activate application" / "Image creation failed" — so
#     you should not be using the screen while it runs. Set
#     KILL_RUNNING_PADBUDDY=1 only when you explicitly want the script to close
#     every existing PadBuddy GUI/headless process first.
#   * Only the *in-app* shots are produced here. The OS-chrome surfaces on the
#     site (menu bar, widget, Control Center, Spotlight, Shortcuts,
#     notifications, the MCP client) are composed separately and are not part of
#     this UI test.
#   * Uses the stable Xcode (DEVELOPER_DIR below) rather than the Xcode-beta the
#     bare `xcodebuild`/`xcrun` resolve to.

set -euo pipefail

# --- Config -----------------------------------------------------------------

# Stable Xcode (26.5). Bare xcodebuild/xcrun resolve to the Xcode-beta toolchain
# on this machine, so pin it explicitly. Override by exporting DEVELOPER_DIR.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="coderpad"
TEST_PLAN="Full"
TEST_PLAN_FILE="${REPO_ROOT}/${TEST_PLAN}.xctestplan"
TEST_ID="coderpadUITests/CoderpadUITests/testCaptureWebsiteHeroLightDark"
ASSETS_DIR="${REPO_ROOT}/docs/assets"
DERIVED_DATA_PATH="${SCREENSHOT_DERIVED_DATA:-${REPO_ROOT}/.build/website-screenshots-derived-data}"

# Maps each attachment name (set via `attachment.name` in the UI test) to the
# docs/assets/ basename it lands as. The two `website-mac-selected-*` captures
# are the theme-aware site hero with a seeded demo pad selected.
# Keep these keys in sync with testCaptureWebsiteHeroLightDark().
declare -a SHOTS=(
  "website-mac-selected-dark:screenshot-pads"
  "website-mac-selected-light:screenshot-pads-light"
)
# The hero is shipped at two widths (see the srcset in docs/index.html).
declare -a HERO_BASENAMES=("screenshot-pads" "screenshot-pads-light")
HERO_2X_WIDTH=2144
HERO_1X_WIDTH=1100

# --- Args -------------------------------------------------------------------

INSTALL=0
EXPORT_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --export-only) EXPORT_ONLY="${2:?--export-only needs an .xcresult path}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/padbuddy-shots.XXXXXX")"
EXPORT_DIR="${STAGING}/exported"
mkdir -p "${EXPORT_DIR}"

# --- Capture (unless we were handed an existing bundle) ---------------------

if [ -n "${EXPORT_ONLY}" ]; then
  RESULT_BUNDLE="${EXPORT_ONLY}"
  [ -e "${RESULT_BUNDLE}" ] || { echo "No such .xcresult: ${RESULT_BUNDLE}" >&2; exit 1; }
  echo "Exporting from existing bundle: ${RESULT_BUNDLE}"
else
  RESULT_BUNDLE="${STAGING}/TestResults.xcresult"

  # Temporarily flip the plan to retain attachments from the passing test, and
  # always put it back — even on failure or Ctrl-C — so we never commit the
  # toggled plan (it bloats every other run's results).
  PLAN_BACKUP="$(mktemp)"
  cp "${TEST_PLAN_FILE}" "${PLAN_BACKUP}"
  USER_SCHEME=""
  USER_SCHEME_BACKUP=""
  restore_state() {
    if [ -f "${PLAN_BACKUP}" ]; then
      cp "${PLAN_BACKUP}" "${TEST_PLAN_FILE}"
      rm -f "${PLAN_BACKUP}"
      echo "Restored ${TEST_PLAN}.xctestplan."
    fi
    if [ -n "${USER_SCHEME_BACKUP}" ] && [ -f "${USER_SCHEME_BACKUP}" ]; then
      mv -f "${USER_SCHEME_BACKUP}" "${USER_SCHEME}"
      echo "Restored user scheme."
    fi
  }
  trap restore_state EXIT

  # A per-user scheme shadows the shared scheme and may not reference Full,
  # making `-testPlan Full` fail. Set it aside for the capture only.
  USER_SCHEME="$(find "${REPO_ROOT}/coderpad.xcodeproj/xcuserdata" \
    -path '*/xcschemes/coderpad.xcscheme' 2>/dev/null | head -1 || true)"
  if [ -n "${USER_SCHEME}" ] && [ -f "${USER_SCHEME}" ]; then
    USER_SCHEME_BACKUP="${STAGING}/coderpad.xcscheme.userbak"
    mv "${USER_SCHEME}" "${USER_SCHEME_BACKUP}"
    echo "Set user scheme aside so the shared ${TEST_PLAN} plan is used."
  fi

  echo "Enabling keepAlways attachments in ${TEST_PLAN}.xctestplan..."
  jq '
    .defaultOptions.userAttachmentLifetime = "keepAlways"
    | .defaultOptions.environmentVariableEntries =
        ((.defaultOptions.environmentVariableEntries // [])
         + [{"key": "CAPTURE_SCREENSHOTS", "value": "1"}])
  ' "${PLAN_BACKUP}" > "${TEST_PLAN_FILE}"

  # Never terminate the user's GUI or headless MCP sessions implicitly. A caller
  # using a dedicated capture machine may explicitly request the old cleanup.
  if [ "${KILL_RUNNING_PADBUDDY:-0}" = "1" ]; then
    pkill -x PadBuddy 2>/dev/null || true
  fi
  # Move the pointer away from the left-side Dock. A lingering Dock tooltip can
  # otherwise be composited into the transparent pixels around rounded windows.
  swift -e 'import CoreGraphics; CGWarpMouseCursorPosition(CGPoint(x: 1000, y: 500))' \
    >/dev/null 2>&1 || true
  sleep 1

  echo "Running ${TEST_ID} (this builds the app and drives the demo account)..."
  set -o pipefail
  CAPTURE_SCREENSHOTS=1 xcodebuild test \
    -project "${REPO_ROOT}/coderpad.xcodeproj" \
    -scheme "${SCHEME}" \
    -testPlan "${TEST_PLAN}" \
    -only-testing:"${TEST_ID}" \
    -destination 'platform=macOS' \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -resultBundlePath "${RESULT_BUNDLE}"

  restore_state
  trap - EXIT
fi

# --- Export attachments -----------------------------------------------------

echo "Exporting attachments..."
xcrun xcresulttool export attachments \
  --path "${RESULT_BUNDLE}" \
  --output-path "${EXPORT_DIR}" >/dev/null

MANIFEST="${EXPORT_DIR}/manifest.json"
[ -f "${MANIFEST}" ] || { echo "No manifest.json produced — nothing to export." >&2; exit 1; }

# Resolve an attachment name (e.g. "pads-detail") to the exported file on disk.
# The manifest is an array of per-test entries, each with an `attachments` list
# carrying `exportedFileName` and `suggestedHumanReadableName`. Match the human
# name as a prefix so a ".png"/suffix doesn't matter.
resolve_export() {
  local want="$1"
  # Recursive descent finds attachment objects whether the manifest is a flat
  # list or nested one-entry-per-test, across xcresulttool versions. Match the
  # human name before xcresulttool's generated `_0_<UUID>.png` suffix. Requiring
  # the underscore boundary prevents "pads-detail" matching a longer shot name.
  jq -r --arg want "${want}" '
    [ .. | objects
      | select(has("exportedFileName"))
      | select((.suggestedHumanReadableName // "") | startswith($want + "_")) ]
    | (.[0].exportedFileName // empty)
  ' "${MANIFEST}"
}

echo ""
echo "Captured screenshots (staging: ${EXPORT_DIR}):"
PLACED=0
for entry in "${SHOTS[@]}"; do
  name="${entry%%:*}"
  dest_base="${entry##*:}"
  file="$(resolve_export "${name}")"
  if [ -z "${file}" ] || [ ! -f "${EXPORT_DIR}/${file}" ]; then
    echo "  - ${name}: (not found in this run)"
    continue
  fi
  src="${EXPORT_DIR}/${file}"
  echo "  - ${name} -> ${dest_base}.png  (${src})"
  PLACED=$((PLACED + 1))

  if [ "${INSTALL}" -eq 1 ]; then
    if [[ " ${HERO_BASENAMES[*]} " == *" ${dest_base} "* ]]; then
      # The hero ships at two widths for its srcset.
      sips --resampleWidth "${HERO_2X_WIDTH}" "${src}" --out "${ASSETS_DIR}/${dest_base}@2x.png" >/dev/null
      sips --resampleWidth "${HERO_1X_WIDTH}" "${src}" --out "${ASSETS_DIR}/${dest_base}.png" >/dev/null
      echo "      installed ${dest_base}.png (${HERO_1X_WIDTH}w) + ${dest_base}@2x.png (${HERO_2X_WIDTH}w)"
    else
      cp "${src}" "${ASSETS_DIR}/${dest_base}.png"
      echo "      installed ${dest_base}.png (full resolution)"
    fi
  fi
done

echo ""
if [ "${PLACED}" -eq 0 ]; then
  echo "No marketing attachments found. If you ran a capture, check that the test"
  echo "wasn't skipped (it skips when GITHUB_ACTIONS is set) and that the GUI"
  echo "session was free." >&2
  exit 1
fi

if [ "${INSTALL}" -eq 1 ]; then
  echo "Installed ${PLACED} screenshot(s) into docs/assets/. Review them, then commit."
else
  echo "Re-run with --install to copy/resize these into docs/assets/, or copy the"
  echo "staged files above by hand. (Default leaves docs/assets/ untouched.)"
fi
