#!/usr/bin/env bash
#
# Validate the entitlements every shipping bundle in an App Store archive will carry.
#
# The archive is built with `CODE_SIGNING_ALLOWED=NO`, because Xcode Cloud owns
# distribution credentials, so no signature is produced and none of the entitlement
# expansion can be read back off the product. The workflow's comment nonetheless claimed
# the step exercised entitlements (#4624). It does not — so the entitlements are validated
# directly here instead: the archive must contain the bundles it should, and each of their
# entitlement files must declare exactly the reviewed keys, with the app group and
# ubiquity identifier this app actually uses.
#
# This does NOT prove profile compatibility or application-identifier expansion. Only a
# signed build can, and that stays with Xcode Cloud.

set -euo pipefail

archive="${1:-}"
platform="${2:-}"
if [[ -z "$archive" || ! -d "$archive" ]] || [[ "$platform" != "macos" && "$platform" != "ios" ]]; then
  echo "usage: $(basename "$0") <path-to-.xcarchive> <macos|ios>" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_group="group.com.adamdangoor.padbuddy"
# Literal: the entitlements file carries the unexpanded build-setting reference, and it
# is that literal we are pinning.
# shellcheck disable=SC2016
kvstore='$(TeamIdentifierPrefix)com.adamdangoor.padbuddy'

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Reviewed keys per bundle. Anything added, removed, or misspelled fails here rather than
# at submission.
if [[ "$platform" == "macos" ]]; then
  app_entitlements="$repo_root/PadBuddy-AppStore.entitlements"
  widget_entitlements="$repo_root/RecentPadsWidgetExtension-AppStore.entitlements"
  expected_app_keys="com.apple.developer.ubiquity-kvstore-identifier
com.apple.security.app-sandbox
com.apple.security.application-groups
com.apple.security.files.user-selected.read-write
com.apple.security.network.client
com.apple.security.print"
else
  app_entitlements="$repo_root/PadBuddy-iOS.entitlements"
  widget_entitlements="$repo_root/RecentPadsWidgetExtension-iOS.entitlements"
  expected_app_keys="com.apple.developer.ubiquity-kvstore-identifier
com.apple.security.application-groups"
fi

check_keys() {
  local file="$1" expected="$2"
  [[ -f "$file" ]] || fail "entitlements file not found: $file"
  plutil -lint "$file" >/dev/null || fail "$file is not a valid property list"

  local actual
  actual="$(plutil -convert json -o - "$file" | jq -r 'keys[]' | sort)"
  if [[ "$actual" != "$(printf '%s\n' "$expected" | sort)" ]]; then
    echo "::error::$file declares unexpected entitlements." >&2
    diff <(printf '%s\n' "$expected" | sort) <(printf '%s\n' "$actual") >&2 || true
    exit 1
  fi
}

check_group_and_kvstore() {
  local file="$1"
  local groups
  groups="$(plutil -convert json -o - "$file" | jq -r '.["com.apple.security.application-groups"][]')"
  [[ "$groups" == "$app_group" ]] \
    || fail "$file must declare exactly the $app_group app group, found: $groups"

  local identifier
  identifier="$(plutil -convert json -o - "$file" \
    | jq -r '.["com.apple.developer.ubiquity-kvstore-identifier"] // empty')"
  if [[ -n "$identifier" && "$identifier" != "$kvstore" ]]; then
    fail "$file declares ubiquity identifier '$identifier', expected '$kvstore'"
  fi
}

check_keys "$app_entitlements" "$expected_app_keys"
check_group_and_kvstore "$app_entitlements"
check_group_and_kvstore "$widget_entitlements"

# The archive must actually contain the bundles those entitlements describe.
app="$(find "$archive/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "$app" ]] || fail "archived app not found under $archive"

if [[ "$platform" == "macos" ]]; then
  plugins="$app/Contents/PlugIns"
else
  plugins="$app/PlugIns"
fi
[[ -d "$plugins/RecentPadsWidgetExtension.appex" ]] \
  || fail "archived app does not contain RecentPadsWidgetExtension.appex"

echo "OK: reviewed entitlements for $platform, and the archive contains the bundles they cover."
