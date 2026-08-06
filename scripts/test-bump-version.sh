#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/scripts" "$fixture/PadBuddy.xcodeproj"
cp "$repo_root/scripts/bump-version.sh" "$fixture/scripts/"
printf 'MARKETING_VERSION = 0.1.14;\nCURRENT_PROJECT_VERSION = 1998;\n' \
  > "$fixture/PadBuddy.xcodeproj/project.pbxproj"
chmod 0644 "$fixture/PadBuddy.xcodeproj/project.pbxproj"

for invalid in 0.08.0 01.2.0 1.0000000000.0 1234567890.1.0; do
  if "$fixture/scripts/bump-version.sh" "$invalid" 2000 >/dev/null 2>&1; then
    echo "expected invalid marketing version '$invalid' to fail" >&2
    exit 1
  fi
done

"$fixture/scripts/bump-version.sh" 0.2.0 2000 >/dev/null
grep -Fq 'MARKETING_VERSION = 0.2.0;' "$fixture/PadBuddy.xcodeproj/project.pbxproj"
grep -Fq 'CURRENT_PROJECT_VERSION = 2000;' "$fixture/PadBuddy.xcodeproj/project.pbxproj"

mode="$(stat -f '%Lp' "$fixture/PadBuddy.xcodeproj/project.pbxproj" 2>/dev/null \
  || stat -c '%a' "$fixture/PadBuddy.xcodeproj/project.pbxproj")"
if [[ "$mode" != 644 ]]; then
  echo "expected project mode 644 after rewrite, got $mode" >&2
  exit 1
fi

echo "Version-bump tests passed."
