#!/usr/bin/env bash

set -euo pipefail

root="${PRIVACY_ROOT:-.}"
project="${PRIVACY_PROJECT_PATH:-$root/PadBuddy.xcodeproj/project.pbxproj}"

fail() {
  echo "error: $*" >&2
  exit 1
}

# The API categories this project has reviewed, each with the reason codes reviewed for
# it. Type-checking alone let a typo — an unknown category, an unknown reason code, or an
# empty reason list — pass CI and fail App Store validation, or quietly misstate what the
# app does (issue #4588). Adding an entry here is the review step.
reviewed_categories='{
  "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
  "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"]
}'

validate_schema() {
  local manifest="$1"
  plutil -lint "$manifest" >/dev/null
  plutil -convert json -o - "$manifest" | jq -e --argjson reviewed "$reviewed_categories" '
    type == "object"
    and .NSPrivacyTracking == false
    and (.NSPrivacyCollectedDataTypes | type == "array" and length == 0)
    and (.NSPrivacyTrackingDomains | type == "array")
    # Apple rejects a tracking domain that is not a plain hostname, and an array of
    # numbers or objects satisfied "is an array" (issue #4587). Duplicates are rejected
    # too: they are always a mistake, and Apple deduplicates them silently.
    and all(.NSPrivacyTrackingDomains[];
      type == "string"
      and test("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$")
      and (length <= 253))
    and ((.NSPrivacyTrackingDomains | unique | length) == (.NSPrivacyTrackingDomains | length))
    # A manifest declaring no tracking must not name tracking domains.
    and (.NSPrivacyTracking or (.NSPrivacyTrackingDomains | length) == 0)
    and (.NSPrivacyAccessedAPITypes | type == "array")
    and all(.NSPrivacyAccessedAPITypes[]; . as $entry
      | type == "object"
      and ($entry.NSPrivacyAccessedAPIType | type == "string")
      and ($reviewed | has($entry.NSPrivacyAccessedAPIType))
      and ($entry.NSPrivacyAccessedAPITypeReasons | type == "array" and length > 0)
      and all($entry.NSPrivacyAccessedAPITypeReasons[]; type == "string")
      and (($entry.NSPrivacyAccessedAPITypeReasons | unique | length)
        == ($entry.NSPrivacyAccessedAPITypeReasons | length))
      and all($entry.NSPrivacyAccessedAPITypeReasons[]; . as $reason
        | $reviewed[$entry.NSPrivacyAccessedAPIType] | index($reason) != null))
    # One entry per category, so two entries cannot disagree about the same API.
    and (([.NSPrivacyAccessedAPITypes[].NSPrivacyAccessedAPIType] | unique | length)
      == (.NSPrivacyAccessedAPITypes | length))
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

app_manifest="$root/PadBuddy/PrivacyInfo.xcprivacy"
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

target_has_synchronized_folder PadBuddy PadBuddy \
  || fail "PadBuddy/PrivacyInfo.xcprivacy is not attached to the PadBuddy target"
target_has_synchronized_folder PadBuddy-AppStore PadBuddy \
  || fail "PadBuddy/PrivacyInfo.xcprivacy is not attached to the PadBuddy-AppStore target"
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

# The watch app attaches its manifest through an explicit build file rather than a
# synchronized folder, so it needs its own structural check. Counting occurrences of
# the build-file comment anywhere in the project was satisfied by attaching
# WatchApp/PrivacyInfo.xcprivacy to *any* target's Resources phase, while the watch
# app itself shipped without one — an App Store submission failure (#4791).
target_resources_phase() {
  local target="$1"
  awk -v target="$target" '
    /isa = PBXNativeTarget;/ { in_target = 1; name = ""; phase = "" }
    in_target && $0 ~ /\/\* Resources \*\/,[[:space:]]*$/ { phase = $1 }
    in_target && $0 ~ /^[[:space:]]*name = / {
      name = $0
      sub(/^[[:space:]]*name = "?/, "", name)
      sub(/"?;[[:space:]]*$/, "", name)
    }
    in_target && /^[[:space:]]*};/ {
      if (name == target && phase != "") { print phase; exit 0 }
      in_target = 0
    }
  ' "$project"
}

# The id of the PBXFileReference for a given path. Resolved by `path =`, never by
# the `/* comment */` beside an id: Xcode rewrites those comments from the file's
# own name whenever it saves the project, so matching on one passes until the first
# time the project is opened and then fails for no real reason.
file_reference_id() {
  local path="$1"
  awk -v path="$path" '
    /isa = PBXFileReference;/ && index($0, "path = " path ";") { print $1; exit }
  ' "$project"
}

# Whether a build phase lists a build file whose fileRef is `ref`.
phase_lists_file_reference() {
  local phase="$1" ref="$2"
  local build_files
  build_files="$(awk -v ref="$ref" '
    /isa = PBXBuildFile;/ && index($0, "fileRef = " ref " ") { print $1 }
  ' "$project")"
  [[ -n "$build_files" ]] || return 1

  local build_file
  for build_file in $build_files; do
    if awk -v phase="$phase" -v file="$build_file" '
      $1 == phase && /= \{/ { in_phase = 1 }
      in_phase && $1 == file { found = 1 }
      in_phase && /^[[:space:]]*\};/ { in_phase = 0 }
      END { exit found ? 0 : 1 }
    ' "$project"; then
      return 0
    fi
  done
  return 1
}

watch_phase="$(target_resources_phase "PadBuddy Watch App")"
[[ -n "$watch_phase" ]] \
  || fail "the PadBuddy Watch App target has no Resources build phase"
watch_manifest_ref="$(file_reference_id WatchApp/PrivacyInfo.xcprivacy)"
[[ -n "$watch_manifest_ref" ]] \
  || fail "no file reference for WatchApp/PrivacyInfo.xcprivacy"
phase_lists_file_reference "$watch_phase" "$watch_manifest_ref" \
  || fail "WatchApp/PrivacyInfo.xcprivacy is not in the watch target's Resources phase"

echo "Privacy manifest gate passed."
