#!/usr/bin/env bash
#
# Regenerate the App Store screenshots (#62): the seeded, PII-free `-uiTesting`
# demo account's main window captured in light mode and in dark mode. It drives
# the testCaptureAppStoreLightDark UI test, exports the captured PNGs, and
# letterboxes each onto a 2880x1800 canvas (a valid macOS App Store screenshot
# size).
#
# (The menu-bar quick-access dropdown is a native `.menu`-style NSMenu, which
# XCUITest cannot screenshot — the captured frame never contains the open menu —
# so it is not produced here.)
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
#   * Uses the stable Xcode (DEVELOPER_DIR below) rather than the Xcode-beta the
#     bare `xcodebuild`/`xcrun` resolve to.

set -euo pipefail

# --- Config -----------------------------------------------------------------

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="PadBuddy"
TEST_PLAN="Full"
TEST_PLAN_FILE="${REPO_ROOT}/${TEST_PLAN}.xctestplan"
# Target/Class/Method. The class is `CoderpadUITests` (capital C) — a lowercase
# class component silently selects 0 tests ("Executed 0 tests").
LIGHTDARK_TEST="PadBuddyUITests/CoderpadUITests/testCaptureAppStoreLightDark"
SHOTS_DIR="${REPO_ROOT}/app-store/submission/en-US/screenshots"

# Target App Store canvas (valid macOS size).
CANVAS_W=2880
CANVAS_H=1800

# Maps each attachment name (set via `attachment.name` in the UI tests) to the
# screenshots/ basename it lands as. Keep in sync with the UI tests.
declare -a SHOTS=(
  "appstore-light:02-main-window-light"
  "appstore-dark:03-main-window-dark"
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
  # Every scheme moved aside, as "<original path>:<backup path>" pairs.
  USER_SCHEME_BACKUPS=()
  restore_state() {
    # Put the toggled test plan back (it bloats every other run's results).
    if [ -n "${PLAN_BACKUP}" ] && [ -f "${PLAN_BACKUP}" ]; then
      cp "${PLAN_BACKUP}" "${TEST_PLAN_FILE}"
      rm -f "${PLAN_BACKUP}"
      echo "Restored ${TEST_PLAN}.xctestplan."
    fi
    # Put every user scheme back so the developer's Xcode is unchanged.
    for pair in "${USER_SCHEME_BACKUPS[@]:-}"; do
      [ -n "${pair}" ] || continue

      original="${pair%%:*}"
      backup="${pair##*:}"
      if [ -f "${backup}" ]; then
        mv -f "${backup}" "${original}"
        echo "Restored user scheme ${original}."
      fi
    done
    USER_SCHEME_BACKUPS=()
  }
  trap restore_state EXIT

  # The shared scheme defines the Fast/Full/TSan test plans, but a per-user scheme
  # (xcuserdata) takes precedence and, lacking any test plans, makes xcodebuild
  # auto-create a single plan named after the scheme — so `-testPlan Full` is then
  # rejected ("no associated test plan named Full") and a passing test's
  # attachments can't be retained. Move the user scheme aside for the run so the
  # shared scheme + Full plan is used deterministically; the trap restores it.
  # Every matching user scheme, not just the first: a project can hold one per macOS
  # user account, and any left behind keeps shadowing the shared scheme (issue #4634).
  USER_SCHEMES=()
  while IFS= read -r candidate; do
    [ -f "${candidate}" ] && USER_SCHEMES+=("${candidate}")
  done < <(find "${REPO_ROOT}/PadBuddy.xcodeproj/xcuserdata" \
    -path '*/xcschemes/PadBuddy.xcscheme' 2>/dev/null || true)
  for index in "${!USER_SCHEMES[@]}"; do
    backup="${STAGING}/PadBuddy.xcscheme.userbak.${index}"
    mv "${USER_SCHEMES[$index]}" "${backup}"
    USER_SCHEME_BACKUPS+=("${USER_SCHEMES[$index]}:${backup}")
  done
  if [ "${#USER_SCHEMES[@]}" -gt 0 ]; then
    echo "Set ${#USER_SCHEMES[@]} user scheme(s) aside so the shared ${TEST_PLAN} plan is used."
  fi

  # Flip the plan to retain attachments from the passing tests.
  PLAN_BACKUP="$(mktemp)"
  cp "${TEST_PLAN_FILE}" "${PLAN_BACKUP}"
  echo "Enabling keepAlways attachments in ${TEST_PLAN}.xctestplan..."
  jq '
    .defaultOptions.userAttachmentLifetime = "keepAlways"
    | .defaultOptions.environmentVariableEntries =
        ((.defaultOptions.environmentVariableEntries // [])
         + [{"key": "CAPTURE_SCREENSHOTS", "value": "1"}])
  ' "${PLAN_BACKUP}" > "${TEST_PLAN_FILE}"

  # Capture needs the foreground to itself, and XCUITest can't disambiguate
  # multiple running instances of the same bundle id (the GUI app and any headless
  # `--mcp` servers all share it) — that surfaces as the runner being killed
  # "before establishing connection".
  #
  # Killing is opt-in. It used to be the default, so simply running this script
  # terminated the user's own running PadBuddy and every headless `--mcp` server
  # another agent had open — the other capture scripts already require an explicit
  # opt-in (issue #4636). Without it, running instances are reported so the failure
  # that follows is at least explicable.
  if [ "${KILL_RUNNING_PADBUDDY:-0}" = "1" ]; then
    pkill -x PadBuddy 2>/dev/null || true
  elif pgrep -x PadBuddy >/dev/null 2>&1; then
    echo "warning: PadBuddy is already running; capture will likely fail to connect." >&2
    echo "warning: quit it, or re-run with KILL_RUNNING_PADBUDDY=1 to terminate every instance." >&2
  fi

  echo "Running App Store capture tests (this builds the app and drives the demo account)..."
  set -o pipefail
  # Let the project's automatic signing sign the app and the XCTRunner. Do NOT
  # disable signing (CODE_SIGNING_ALLOWED=NO): on Apple Silicon an unsigned
  # binary cannot launch, and the runner is rejected at launch with the Gatekeeper
  # "PadBuddyUITests-Runner is damaged and can't be opened" dialog — which
  # surfaces as the runner being killed "before establishing connection".
  CAPTURE_SCREENSHOTS=1 \
  XCODEBUILD_BIN=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  "${REPO_ROOT}/scripts/run-xcodebuild.sh" \
    "${RESULT_BUNDLE%.xcresult}.log" test \
    -quiet \
    -showBuildTimingSummary \
    -project "${REPO_ROOT}/PadBuddy.xcodeproj" \
    -scheme "${SCHEME}" \
    -testPlan "${TEST_PLAN}" \
    -only-testing:"${LIGHTDARK_TEST}" \
    -destination 'platform=macOS,arch=arm64' \
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

# Resolve an attachment name to the exported file on disk. XCTest mangles the
# `attachment.name` we set into `<name>_<index>_<UUID>.<ext>` in the manifest's
# suggestedHumanReadableName, so strip that trailing `_<idx>_<UUID>` (and the
# extension) before comparing by equality — a plain extension-strip equality
# never matches, and a bare prefix match would let "x" grab "x-large".
resolve_export() {
  local want="$1"
  jq -r --arg want "${want}" '
    [ .. | objects
      | select(has("exportedFileName"))
      | select(((.suggestedHumanReadableName // "")
          | sub("(_[0-9]+_[0-9A-Fa-f-]+)?\\.[^.]*$"; "")) == $want) ]
    | if length == 1 then .[0].exportedFileName else empty end
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

resolved_files=()
for entry in "${SHOTS[@]}"; do
  name="${entry%%:*}"
  file="$(resolve_export "${name}")"
  if [ -z "${file}" ] || [ ! -f "${EXPORT_DIR}/${file}" ]; then
    echo "Missing required App Store attachment: ${name}" >&2
    exit 1
  fi
  resolved_files+=("${EXPORT_DIR}/${file}")
done

mkdir -p "${SHOTS_DIR}"
# Convert into a staging directory first. Deleting the previous set and letterboxing
# one-by-one into the final paths meant a `sips` failure part-way left the submission
# directory missing files or half-updated — with the old, complete set already gone
# (issue #4635). The old set is only replaced once every conversion has succeeded.
CONVERTED_DIR="${STAGING}/converted"
mkdir -p "${CONVERTED_DIR}"
for index in "${!SHOTS[@]}"; do
  entry="${SHOTS[$index]}"
  dest_base="${entry##*:}"
  letterbox "${resolved_files[$index]}" "${CONVERTED_DIR}/${dest_base}-${CANVAS_W}x${CANVAS_H}.png"
done

rm -f "${SHOTS_DIR}/01-main-window-${CANVAS_W}x${CANVAS_H}.png"
echo ""
echo "App Store screenshots:"
PLACED=0
for entry in "${SHOTS[@]}"; do
  name="${entry%%:*}"
  dest_base="${entry##*:}"
  dest="${SHOTS_DIR}/${dest_base}-${CANVAS_W}x${CANVAS_H}.png"
  mv -f "${CONVERTED_DIR}/${dest_base}-${CANVAS_W}x${CANVAS_H}.png" "${dest}"
  echo "  - ${name} -> ${dest}"
  PLACED=$((PLACED + 1))
done

echo ""
echo "Wrote ${PLACED} screenshot(s) to ${SHOTS_DIR}. Review them, then commit."
