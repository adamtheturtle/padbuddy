#!/usr/bin/env bash

set -euo pipefail

root="${PRIVACY_ROOT:-.}"
project="${PRIVACY_PROJECT_PATH:-$root/coderpad.xcodeproj/project.pbxproj}"

fail() {
  echo "error: $*" >&2
  exit 1
}

validate_schema() {
  local manifest="$1"
  plutil -lint "$manifest" >/dev/null
  plutil -convert json -o - "$manifest" | jq -e '
    type == "object"
    and .NSPrivacyTracking == false
    and (.NSPrivacyCollectedDataTypes | type == "array" and length == 0)
    and (.NSPrivacyTrackingDomains | type == "array")
    and (.NSPrivacyAccessedAPITypes | type == "array")
    and all(.NSPrivacyAccessedAPITypes[];
      type == "object"
      and (.NSPrivacyAccessedAPIType | type == "string")
      and (.NSPrivacyAccessedAPITypeReasons | type == "array")
      and all(.NSPrivacyAccessedAPITypeReasons[]; type == "string"))
  ' >/dev/null || fail "$manifest has an invalid or unreviewed privacy schema"
}

require_reason() {
  local manifest="$1" category="$2" reason="$3"
  plutil -convert json -o - "$manifest" | jq -e --arg category "$category" --arg reason "$reason" '
    any(.NSPrivacyAccessedAPITypes[];
      .NSPrivacyAccessedAPIType == $category
      and (.NSPrivacyAccessedAPITypeReasons | type == "array")
      and (.NSPrivacyAccessedAPITypeReasons | index($reason) != null))
  ' >/dev/null || fail "$manifest must declare $category reason $reason"
}

app_manifest="$root/coderpad/PrivacyInfo.xcprivacy"
widget_manifest="$root/RecentPadsWidget/PrivacyInfo.xcprivacy"
watch_manifest="$root/WatchApp/PrivacyInfo.xcprivacy"

for manifest in "$app_manifest" "$widget_manifest" "$watch_manifest"; do
  validate_schema "$manifest"
done
require_reason "$app_manifest" NSPrivacyAccessedAPICategoryFileTimestamp C617.1
require_reason "$app_manifest" NSPrivacyAccessedAPICategoryUserDefaults CA92.1
require_reason "$widget_manifest" NSPrivacyAccessedAPICategoryFileTimestamp C617.1
require_reason "$watch_manifest" NSPrivacyAccessedAPICategoryUserDefaults CA92.1

target_has_synchronized_folder() {
  local target="$1" folder="$2"
  awk -v target="$target" -v folder="$folder" '
    /isa = PBXNativeTarget;/ { in_target = 1; has_folder = 0; has_name = 0 }
    in_target && index($0, "/* " folder " */") { has_folder = 1 }
    in_target && $0 ~ /^[[:space:]]*name = / {
      name = $0
      sub(/^[[:space:]]*name = "?/, "", name)
      sub(/"?;[[:space:]]*$/, "", name)
      if (name == target) has_name = 1
    }
    in_target && /^[[:space:]]*};/ {
      if (has_folder && has_name) found = 1
      in_target = 0
    }
    END { exit found ? 0 : 1 }
  ' "$project"
}

target_has_synchronized_folder coderpad coderpad \
  || fail "coderpad/PrivacyInfo.xcprivacy is not attached to the coderpad target"
target_has_synchronized_folder CoderPad-AppStore coderpad \
  || fail "coderpad/PrivacyInfo.xcprivacy is not attached to the CoderPad-AppStore target"
target_has_synchronized_folder RecentPadsWidgetExtension RecentPadsWidget \
  || fail "RecentPadsWidget/PrivacyInfo.xcprivacy is not attached to the widget target"

if awk '
  /membershipExceptions = \(/ { in_exceptions = 1 }
  in_exceptions && /PrivacyInfo\.xcprivacy/ { found = 1 }
  in_exceptions && /\);/ { in_exceptions = 0 }
  END { exit found ? 0 : 1 }
' "$project"; then
  fail "a privacy manifest is excluded from a synchronized target"
fi

watch_resource_count="$(grep -c 'WatchPrivacyInfo.xcprivacy in Resources' "$project" || true)"
[[ "$watch_resource_count" -ge 2 ]] \
  || fail "WatchApp/PrivacyInfo.xcprivacy is not attached to the watch Resources phase"

echo "Privacy manifest gate passed."
