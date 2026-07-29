#!/usr/bin/env bash

set -euo pipefail

for manifest in coderpad/PrivacyInfo.xcprivacy RecentPadsWidget/PrivacyInfo.xcprivacy; do
  plutil -lint "$manifest" >/dev/null

  if ! plutil -convert json -o - "$manifest" |
    jq -e '
      .NSPrivacyAccessedAPITypes[]
      | select(.NSPrivacyAccessedAPIType == "NSPrivacyAccessedAPICategoryFileTimestamp")
      | .NSPrivacyAccessedAPITypeReasons
      | index("C617.1")
    ' >/dev/null; then
    echo "error: $manifest must declare file-timestamp reason C617.1." >&2
    exit 1
  fi
done

echo "Privacy manifest gate passed."
