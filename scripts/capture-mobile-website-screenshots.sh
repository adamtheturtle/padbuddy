#!/usr/bin/env bash
#
# Regenerate the website's iPad and iPhone hero screenshots in light and dark
# mode. Both destinations run the same XCUITest, which always launches PadBuddy
# with `-uiTesting`; the captures therefore use the seeded demo account and
# never contain live CoderPad customer or candidate data.
#
# Usage:
#   scripts/capture-mobile-website-screenshots.sh
#       Capture and export to a temporary staging directory.
#   scripts/capture-mobile-website-screenshots.sh --install
#       Capture, export, resize, and install all four files into docs/assets/.
#   scripts/capture-mobile-website-screenshots.sh \
#       --export-only <ipad.xcresult> <iphone.xcresult> [--install]
#       Re-export existing result bundles without running the simulators.
#
# Override the simulator destinations when necessary:
#   IPAD_DESTINATION='platform=iOS Simulator,name=...,OS=...' \
#   IPHONE_DESTINATION='platform=iOS Simulator,name=...,OS=...' \
#     scripts/capture-mobile-website-screenshots.sh --install

set -euo pipefail

# Use the developer's active Xcode so its iOS and watchOS runtimes match (the
# iOS app embeds the Watch app). Callers can still pin a toolchain explicitly.
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${REPO_ROOT}/coderpad.xcodeproj"
SCHEME="coderpad-iPad-Screenshots"
TEST_PLAN="IPadScreenshots"
TEST_ID="coderpadUITests/CoderpadIPadUITests/testCaptureWebsiteLightDarkScreenshots"
ASSETS_DIR="${REPO_ROOT}/docs/assets"

IPAD_DESTINATION="${IPAD_DESTINATION:-}"
IPHONE_DESTINATION="${IPHONE_DESTINATION:-}"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/padbuddy-mobile-shots.XXXXXX")"
DERIVED_DATA_PATH="${SCREENSHOT_DERIVED_DATA:-${STAGING}/DerivedData}"
INSTALL_DIR="${STAGING}/install"
INSTALL=0
EXPORT_ONLY_IPAD=""
EXPORT_ONLY_IPHONE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --install)
      INSTALL=1
      shift
      ;;
    --export-only)
      EXPORT_ONLY_IPAD="${2:?--export-only needs iPad and iPhone .xcresult paths}"
      EXPORT_ONLY_IPHONE="${3:?--export-only needs iPad and iPhone .xcresult paths}"
      shift 3
      ;;
    -h|--help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

capture() {
  local platform="$1" destination="$2" result_bundle="$3"
  echo "Capturing seeded ${platform} light/dark screenshots..."
  xcodebuild test \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -testPlan "${TEST_PLAN}" \
    -only-testing:"${TEST_ID}" \
    -destination "${destination}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -resultBundlePath "${result_bundle}"
}

discover_destination() {
  local family="$1" selected udid name runtime
  selected="$(xcrun simctl list devices available -j | jq -cer --arg family "${family}" '
    [.devices | to_entries[] as $runtime | $runtime.value[]
      | select((.isAvailable // true) and (.name | startswith($family)))
      | . + {runtime: $runtime.key,
             version: ($runtime.key | capture("iOS-(?<value>[0-9-]+)$").value
               | split("-") | map(tonumber))}]
    | sort_by(.version, .name, .udid)
    | last
  ')" || {
    echo "No available ${family} simulator was found; set its destination override explicitly." >&2
    return 1
  }
  udid="$(jq -r .udid <<< "${selected}")"
  name="$(jq -r .name <<< "${selected}")"
  runtime="$(jq -r .runtime <<< "${selected}")"
  echo "Selected ${name} (${runtime}, ${udid}) for ${family} capture." >&2
  printf 'platform=iOS Simulator,id=%s' "${udid}"
}

if [ -n "${EXPORT_ONLY_IPAD}" ]; then
  IPAD_RESULT="${EXPORT_ONLY_IPAD}"
  IPHONE_RESULT="${EXPORT_ONLY_IPHONE}"
  [ -e "${IPAD_RESULT}" ] || { echo "No such iPad result: ${IPAD_RESULT}" >&2; exit 1; }
  [ -e "${IPHONE_RESULT}" ] || { echo "No such iPhone result: ${IPHONE_RESULT}" >&2; exit 1; }
else
  IPAD_DESTINATION="${IPAD_DESTINATION:-$(discover_destination "iPad")}"
  IPHONE_DESTINATION="${IPHONE_DESTINATION:-$(discover_destination "iPhone")}"
  IPAD_RESULT="${STAGING}/iPad.xcresult"
  IPHONE_RESULT="${STAGING}/iPhone.xcresult"
  capture "iPad" "${IPAD_DESTINATION}" "${IPAD_RESULT}"
  capture "iPhone" "${IPHONE_DESTINATION}" "${IPHONE_RESULT}"
fi

export_attachments() {
  local result_bundle="$1" export_dir="$2"
  mkdir -p "${export_dir}"
  xcrun xcresulttool export attachments \
    --path "${result_bundle}" \
    --output-path "${export_dir}" >/dev/null
  [ -f "${export_dir}/manifest.json" ] || {
    echo "No attachment manifest exported from ${result_bundle}." >&2
    exit 1
  }
}

IPAD_EXPORT="${STAGING}/exported-ipad"
IPHONE_EXPORT="${STAGING}/exported-iphone"
export_attachments "${IPAD_RESULT}" "${IPAD_EXPORT}"
export_attachments "${IPHONE_RESULT}" "${IPHONE_EXPORT}"

resolve_export() {
  local export_dir="$1" want="$2"
  jq -r --arg want "${want}" '
    [ .. | objects
      | select(has("exportedFileName"))
      | select(((.suggestedHumanReadableName // "")
          | sub("(_[0-9]+_[0-9A-Fa-f-]+)?\\.[^.]*$"; "")) == $want) ]
    | if length == 1 then .[0].exportedFileName else empty end
  ' "${export_dir}/manifest.json"
}

install_or_report() {
  local export_dir="$1" attachment="$2" dest_name="$3" width="$4"
  local height="${5:-}" rotation="${6:-}"
  local exported_file source prepared destination
  exported_file="$(resolve_export "${export_dir}" "${attachment}")"
  if [ -z "${exported_file}" ] || [ ! -f "${export_dir}/${exported_file}" ]; then
    echo "Missing required attachment: ${attachment}" >&2
    return 1
  fi
  source="${export_dir}/${exported_file}"
  prepared="${source}"

  if [ "${INSTALL}" -eq 1 ]; then
    if [ -n "${rotation}" ]; then
      prepared="${STAGING}/rotated-${dest_name}"
      sips --rotate "${rotation}" "${source}" --out "${prepared}" >/dev/null
    fi
    mkdir -p "${INSTALL_DIR}"
    destination="${INSTALL_DIR}/${dest_name}"
    sips --resampleWidth "${width}" "${prepared}" --out "${destination}" >/dev/null
    if [ -n "${height}" ]; then
      sips --cropToHeightWidth "${height}" "${width}" --cropOffset 0 0 "${destination}" >/dev/null
    fi
    echo "  ${attachment} -> docs/assets/${dest_name}"
  else
    echo "  ${attachment}: ${source}"
  fi
}

echo "Mobile website screenshots:"
install_or_report "${IPAD_EXPORT}" "website-ipad-dark" "screenshot-ipad.png" 1376 "" 270
install_or_report "${IPAD_EXPORT}" "website-ipad-dark" "screenshot-ipad@2x.png" 2752 "" 270
install_or_report "${IPAD_EXPORT}" "website-ipad-light" "screenshot-ipad-light.png" 1376 "" 270
install_or_report "${IPAD_EXPORT}" "website-ipad-light" "screenshot-ipad-light@2x.png" 2752 "" 270
install_or_report "${IPHONE_EXPORT}" "website-iphone-dark" "screenshot-iphone.png" 440 956
install_or_report "${IPHONE_EXPORT}" "website-iphone-dark" "screenshot-iphone@2x.png" 880 1912
install_or_report "${IPHONE_EXPORT}" "website-iphone-light" "screenshot-iphone-light.png" 440 956
install_or_report "${IPHONE_EXPORT}" "website-iphone-light" "screenshot-iphone-light@2x.png" 880 1912

if [ "${INSTALL}" -eq 1 ]; then
  expected=(
    screenshot-ipad.png screenshot-ipad@2x.png screenshot-ipad-light.png screenshot-ipad-light@2x.png
    screenshot-iphone.png screenshot-iphone@2x.png screenshot-iphone-light.png screenshot-iphone-light@2x.png
  )
  backup_dir="${STAGING}/install-backup"
  mkdir -p "${backup_dir}"
  for name in "${expected[@]}"; do
    [ -s "${INSTALL_DIR}/${name}" ] || { echo "Missing staged asset: ${name}" >&2; exit 1; }
    [ -f "${ASSETS_DIR}/${name}" ] || { echo "Existing asset missing: ${name}" >&2; exit 1; }
    cp -p "${ASSETS_DIR}/${name}" "${backup_dir}/${name}"
  done
  transaction_active=1
  rollback_install() {
    if [ "${transaction_active}" -eq 1 ]; then
      echo "Screenshot installation failed; restoring the previous complete set." >&2
      for name in "${expected[@]}"; do
        cp -p "${backup_dir}/${name}" "${ASSETS_DIR}/${name}"
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
  echo "Installed the complete seeded iPad/iPhone light/dark set. Review, then commit."
else
  echo "Staged exports in ${STAGING}. Re-run with --install to update docs/assets/."
fi
