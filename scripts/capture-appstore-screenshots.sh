#!/usr/bin/env bash
#
# Regenerate the App Store screenshots (#62): the seeded, PII-free `-uiTesting`
# demo account captured as a light-mode window, a dark-mode window, and the
# menu-bar quick-access dropdown. It drives two UI tests, exports the captured
# PNGs, and letterboxes each onto a 2880x1800 canvas (a valid macOS App Store
# screenshot size).
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
# then resizes the results, so refreshing the shots is one command.
#
# Usage:
#   scripts/capture-appstore-screenshots.sh                 # capture, export, write to app-store/.../screenshots/
#   scripts/capture-appstore-screenshots.sh --export-only <result.xcresult>
#                                                           # skip the capture; just export/resize from a bundle
#
# Notes:
#   * Run on a FREE GUI session. If another process is driving the app, capture
#     fails with "Failed to activate application" / "Image creation failed" — so
#     this script pre-kills stray PadBuddy instances and you should not be using
#     the screen while it runs.
#   * The menu-bar shot opens a native status-item dropdown, the flakiest step;
#     it is captured by a separate test so a failure there can't lose the
#     light/dark window shots.
#   * Uses the stable Xcode (DEVELOPER_DIR below) rather than the Xcode-beta the
#     bare `xcodebuild`/`xcrun` resolve to.

set -euo pipefail

# --- Config -----------------------------------------------------------------

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="coderpad"
TEST_PLAN="Full"
TEST_PLAN_FILE="${REPO_ROOT}/${TEST_PLAN}.xctestplan"
LIGHTDARK_TEST="coderpadUITests/coderpadUITests/testCaptureAppStoreLightDark"
MENUBAR_TEST="coderpadUITests/coderpadUITests/testCaptureAppStoreMenuBar"
SHOTS_DIR="${REPO_ROOT}/app-store/submission/en-US/screenshots"

# Target App Store canvas (valid macOS size).
CANVAS_W=2880
CANVAS_H=1800

# Maps each attachment name (set via `attachment.name` in the UI tests) to the
# screenshots/ basename it lands as. Keep in sync with the UI tests.
declare -a SHOTS=(
  "appstore-light:02-main-window-light"
  "appstore-dark:03-main-window-dark"
  "appstore-menubar:04-menu-bar"
)

# --- Args -------------------------------------------------------------------

EXPORT_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --export-only) EXPORT_ONLY="${2:?--export-only needs an .xcresult path}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/padbuddy-appstore.XXXXXX")"
EXPORT_DIR="${STAGING}/exported"
mkdir -p "${EXPORT_DIR}"

# --- Capture (unless we were handed an existing bundle) ---------------------

if [ -n "${EXPORT_ONLY}" ]; then
  RESULT_BUNDLE="${EXPORT_ONLY}"
  [ -e "${RESULT_BUNDLE}" ] || { echo "No such .xcresult: ${RESULT_BUNDLE}" >&2; exit 1; }
  echo "Exporting from existing bundle: ${RESULT_BUNDLE}"
else
  RESULT_BUNDLE="${STAGING}/TestResults.xcresult"

  # State we may temporarily change and must always restore — even on failure or
  # Ctrl-C — registered with a single EXIT trap.
  PLAN_BACKUP=""
  USER_SCHEME=""
  USER_SCHEME_BACKUP=""
  restore_state() {
    # Put the toggled test plan back (it bloats every other run's results).
    if [ -n "${PLAN_BACKUP}" ] && [ -f "${PLAN_BACKUP}" ]; then
      cp "${PLAN_BACKUP}" "${TEST_PLAN_FILE}"
      rm -f "${PLAN_BACKUP}"
      echo "Restored ${TEST_PLAN}.xctestplan."
    fi
    # Put the user scheme back so the developer's Xcode is unchanged.
    if [ -n "${USER_SCHEME_BACKUP}" ] && [ -f "${USER_SCHEME_BACKUP}" ]; then
      mv -f "${USER_SCHEME_BACKUP}" "${USER_SCHEME}"
      echo "Restored user scheme."
    fi
  }
  trap restore_state EXIT

  # The shared scheme defines the Fast/Full/TSan test plans, but a per-user scheme
  # (xcuserdata) takes precedence and, lacking any test plans, makes xcodebuild
  # auto-create a single plan named after the scheme — so `-testPlan Full` is then
  # rejected ("no associated test plan named Full") and a passing test's
  # attachments can't be retained. Move the user scheme aside for the run so the
  # shared scheme + Full plan is used deterministically; the trap restores it.
  USER_SCHEME="$(find "${REPO_ROOT}/coderpad.xcodeproj/xcuserdata" \
    -path '*/xcschemes/coderpad.xcscheme' 2>/dev/null | head -1 || true)"
  if [ -n "${USER_SCHEME}" ] && [ -f "${USER_SCHEME}" ]; then
    USER_SCHEME_BACKUP="${STAGING}/coderpad.xcscheme.userbak"
    mv "${USER_SCHEME}" "${USER_SCHEME_BACKUP}"
    echo "Set user scheme aside so the shared ${TEST_PLAN} plan is used."
  fi

  # Flip the plan to retain attachments from the passing tests.
  PLAN_BACKUP="$(mktemp)"
  cp "${TEST_PLAN_FILE}" "${PLAN_BACKUP}"
  echo "Enabling keepAlways attachments in ${TEST_PLAN}.xctestplan..."
  jq '.defaultOptions.userAttachmentLifetime = "keepAlways"' "${PLAN_BACKUP}" > "${TEST_PLAN_FILE}"

  # Capture needs the foreground to itself, and XCUITest can't disambiguate
  # multiple running instances of the same bundle id (the GUI app and any headless
  # `--mcp` servers all share it) — that surfaces as the runner being killed
  # "before establishing connection". Clear stray instances first. Set SKIP_PKILL=1
  # to leave them alone (e.g. to preserve another agent's `--mcp` servers), but
  # then capture will likely fail unless the session is otherwise quiet.
  if [ "${SKIP_PKILL:-0}" != "1" ]; then
    pkill -x PadBuddy 2>/dev/null || true
  fi

  echo "Running App Store capture tests (this builds the app and drives the demo account)..."
  set -o pipefail
  # Let the project's automatic signing sign the app and the XCTRunner. Do NOT
  # disable signing (CODE_SIGNING_ALLOWED=NO): on Apple Silicon an unsigned
  # binary cannot launch, and the runner is rejected at launch with the Gatekeeper
  # "coderpadUITests-Runner is damaged and can't be opened" dialog — which
  # surfaces as the runner being killed "before establishing connection".
  /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test \
    -project "${REPO_ROOT}/coderpad.xcodeproj" \
    -scheme "${SCHEME}" \
    -testPlan "${TEST_PLAN}" \
    -only-testing:"${LIGHTDARK_TEST}" \
    -only-testing:"${MENUBAR_TEST}" \
    -destination 'platform=macOS,arch=arm64' \
    -resultBundlePath "${RESULT_BUNDLE}" \
    || echo "WARNING: xcodebuild reported a failure (the menu-bar test can be flaky); continuing to export whatever was captured." >&2

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

# Resolve an attachment name to the exported file on disk. Match the human name
# with its extension stripped, by equality (a prefix match would cross-grab).
resolve_export() {
  local want="$1"
  jq -r --arg want "${want}" '
    [ .. | objects
      | select(has("exportedFileName"))
      | select(((.suggestedHumanReadableName // "") | sub("\\.[^.]*$"; "")) == $want) ]
    | (.[0].exportedFileName // empty)
  ' "${MANIFEST}"
}

# Letterbox a capture onto the CANVAS_W x CANVAS_H black canvas: scale to fit
# preserving aspect, then pad the remaining edge with black.
letterbox() {
  local src="$1" dest="$2"
  local w h
  w="$(sips -g pixelWidth "${src}" | awk '/pixelWidth/{print $2}')"
  h="$(sips -g pixelHeight "${src}" | awk '/pixelHeight/{print $2}')"
  local fitted="${STAGING}/fitted.png"
  # Width-constrained when the source is wider than the canvas aspect, else
  # height-constrained. `--resampleWidth/Height` preserve aspect.
  if [ "$(( w * CANVAS_H ))" -ge "$(( h * CANVAS_W ))" ]; then
    sips --resampleWidth "${CANVAS_W}" "${src}" --out "${fitted}" >/dev/null
  else
    sips --resampleHeight "${CANVAS_H}" "${src}" --out "${fitted}" >/dev/null
  fi
  sips --padToHeightWidth "${CANVAS_H}" "${CANVAS_W}" --padColor 000000 "${fitted}" --out "${dest}" >/dev/null
}

mkdir -p "${SHOTS_DIR}"

echo ""
echo "App Store screenshots:"
PLACED=0
for entry in "${SHOTS[@]}"; do
  name="${entry%%:*}"
  dest_base="${entry##*:}"
  file="$(resolve_export "${name}")"
  if [ -z "${file}" ] || [ ! -f "${EXPORT_DIR}/${file}" ]; then
    echo "  - ${name}: (not found in this run)"
    continue
  fi
  dest="${SHOTS_DIR}/${dest_base}-${CANVAS_W}x${CANVAS_H}.png"
  letterbox "${EXPORT_DIR}/${file}" "${dest}"
  echo "  - ${name} -> ${dest}"
  PLACED=$((PLACED + 1))
done

echo ""
if [ "${PLACED}" -eq 0 ]; then
  echo "No App Store attachments found. If you ran a capture, check that the tests" >&2
  echo "weren't skipped (they skip when GITHUB_ACTIONS is set) and that the GUI" >&2
  echo "session was free." >&2
  exit 1
fi

echo "Wrote ${PLACED} screenshot(s) to ${SHOTS_DIR}. Review them, then commit."
