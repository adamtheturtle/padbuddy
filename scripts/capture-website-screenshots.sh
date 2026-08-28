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
SCHEME="PadBuddy"
TEST_PLAN="Full"
TEST_PLAN_FILE="${REPO_ROOT}/${TEST_PLAN}.xctestplan"
TEST_ID="PadBuddyUITests/CoderpadUITests/testCaptureWebsiteHeroLightDark"
ASSETS_DIR="${REPO_ROOT}/docs/assets"
DERIVED_DATA_PATH="${SCREENSHOT_DERIVED_DATA:-}"

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
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${STAGING}/DerivedData}"
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
  USER_SCHEMES=()
  USER_SCHEME_BACKUPS=()
  restore_state() {
    if [ -f "${PLAN_BACKUP}" ]; then
      cp "${PLAN_BACKUP}" "${TEST_PLAN_FILE}"
      rm -f "${PLAN_BACKUP}"
      echo "Restored ${TEST_PLAN}.xctestplan."
    fi
    for index in "${!USER_SCHEMES[@]}"; do
      if [ -f "${USER_SCHEME_BACKUPS[$index]}" ]; then
        mv -f "${USER_SCHEME_BACKUPS[$index]}" "${USER_SCHEMES[$index]}"
      fi
    done
    [ "${#USER_SCHEMES[@]}" -eq 0 ] || echo "Restored ${#USER_SCHEMES[@]} user scheme(s)."
  }
  trap restore_state EXIT

  # A per-user scheme shadows the shared scheme and may not reference Full,
  # making `-testPlan Full` fail. Set it aside for the capture only.
  while IFS= read -r user_scheme; do
    [ -n "${user_scheme}" ] || continue
    index="${#USER_SCHEMES[@]}"
    backup="${STAGING}/PadBuddy.xcscheme.userbak.${index}"
    USER_SCHEMES+=("${user_scheme}")
    USER_SCHEME_BACKUPS+=("${backup}")
    mv "${user_scheme}" "${backup}"
  done < <(find "${REPO_ROOT}/PadBuddy.xcodeproj/xcuserdata" \
    -path '*/xcschemes/PadBuddy.xcscheme' -print 2>/dev/null | sort)
  [ "${#USER_SCHEMES[@]}" -eq 0 ] \
    || echo "Set ${#USER_SCHEMES[@]} user scheme(s) aside so the shared ${TEST_PLAN} plan is used."

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
  CAPTURE_SCREENSHOTS=1 "${REPO_ROOT}/scripts/run-xcodebuild.sh" \
    "${RESULT_BUNDLE%.xcresult}.log" test \
    -quiet \
    -showBuildTimingSummary \
    -project "${REPO_ROOT}/PadBuddy.xcodeproj" \
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
    | if length == 1 then .[0].exportedFileName else empty end
  ' "${MANIFEST}"
}

echo ""
echo "Captured screenshots (staging: ${EXPORT_DIR}):"
resolved_files=()
for entry in "${SHOTS[@]}"; do
  name="${entry%%:*}"
  file="$(resolve_export "${name}")"
  if [ -z "${file}" ] || [ ! -f "${EXPORT_DIR}/${file}" ]; then
    echo "Missing required website attachment: ${name}" >&2
    exit 1
  fi
  resolved_files+=("${EXPORT_DIR}/${file}")
done

INSTALL_DIR="${STAGING}/install"
[ "${INSTALL}" -eq 0 ] || mkdir -p "${INSTALL_DIR}"
PLACED=0
for index in "${!SHOTS[@]}"; do
  entry="${SHOTS[$index]}"
  name="${entry%%:*}"
  dest_base="${entry##*:}"
  src="${resolved_files[$index]}"
  echo "  - ${name} -> ${dest_base}.png  (${src})"
  PLACED=$((PLACED + 1))

  if [ "${INSTALL}" -eq 1 ]; then
    if [[ " ${HERO_BASENAMES[*]} " == *" ${dest_base} "* ]]; then
      # The hero ships at two widths for its srcset.
      sips --resampleWidth "${HERO_2X_WIDTH}" "${src}" --out "${INSTALL_DIR}/${dest_base}@2x.png" >/dev/null
      sips --resampleWidth "${HERO_1X_WIDTH}" "${src}" --out "${INSTALL_DIR}/${dest_base}.png" >/dev/null
    else
      cp "${src}" "${INSTALL_DIR}/${dest_base}.png"
    fi
  fi
done

echo ""
if [ "${INSTALL}" -eq 1 ]; then
  expected=(
    screenshot-pads.png screenshot-pads@2x.png
    screenshot-pads-light.png screenshot-pads-light@2x.png
  )
  backup_dir="${STAGING}/install-backup"
  mkdir -p "${backup_dir}"
  # An asset that does not exist yet is a first install, not an error: a fresh checkout,
  # a newly introduced asset, or one deliberately deleted because it was corrupt could
  # not be generated by the documented `--install` command at all (issue #4639).
  # Rollback removes those rather than restoring a backup that never existed.
  created=()
  for name in "${expected[@]}"; do
    [ -s "${INSTALL_DIR}/${name}" ] || { echo "Missing staged asset: ${name}" >&2; exit 1; }
    if [ -f "${ASSETS_DIR}/${name}" ]; then
      cp -p "${ASSETS_DIR}/${name}" "${backup_dir}/${name}"
    else
      created+=("${name}")
      echo "docs/assets/${name} does not exist yet; it will be created."
    fi
  done
  transaction_active=1
  rollback_install() {
    if [ "${transaction_active}" -eq 1 ]; then
      echo "Screenshot installation failed; restoring the previous set." >&2
      for name in "${expected[@]}"; do
        if [ -f "${backup_dir}/${name}" ]; then
          cp -p "${backup_dir}/${name}" "${ASSETS_DIR}/${name}"
        fi
      done
      for name in "${created[@]:-}"; do
        [ -n "${name}" ] && rm -f "${ASSETS_DIR}/${name}"
      done
    fi
  }
  trap rollback_install EXIT
  for name in "${expected[@]}"; do
    temporary="${ASSETS_DIR}/.${name}.installing.$$"
    cp "${INSTALL_DIR}/${name}" "${temporary}"
    mv -f "${temporary}" "${ASSETS_DIR}/${name}"
  done
  transaction_active=0
  trap - EXIT
  # The staging tree holds a whole DerivedData directory, the xcresult bundles, and every
  # exported and resized image — gigabytes with nothing left to use them for once the
  # install succeeded, and that nothing ever removed (issue #4638). Set
  # KEEP_SCREENSHOT_STAGING=1 to inspect it.
  if [ "${KEEP_SCREENSHOT_STAGING:-0}" = "1" ]; then
    echo "Kept the staging tree at ${STAGING}."
  else
    rm -rf "${STAGING}"
  fi
  echo "Installed ${PLACED} screenshot(s) into docs/assets/. Review them, then commit."
else
  echo "Re-run with --install to copy/resize these into docs/assets/, or copy the"
  echo "staged files above by hand. (Default leaves docs/assets/ untouched.)"
fi
