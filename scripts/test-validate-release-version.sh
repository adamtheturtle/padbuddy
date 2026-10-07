#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$repo_root/scripts/validate-release-version.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cd "$fixture"
git init -q
git config user.email test@example.com
git config user.name Test
# The fixture must not depend on the developer's signing setup: a configured signing
# key (or an unavailable agent) would otherwise fail these commits.
git config commit.gpgsign false
git config tag.gpgsign false
mkdir PadBuddy.xcodeproj
printf 'CURRENT_PROJECT_VERSION = 10000;\n' > PadBuddy.xcodeproj/project.pbxproj
git add PadBuddy.xcodeproj/project.pbxproj
git commit -qm initial
git tag v1.0.0

if "$validator" 1.0.1 5000 v1.0.1 >output 2>&1; then
  echo "expected a build below the tagged CURRENT_PROJECT_VERSION to fail" >&2
  exit 1
fi
grep -Fq "prior upload build '10000'" output

"$validator" 1.0.1 10001 v1.0.1 >/dev/null

for invalid in 0 08 09 0001 2147483648 999999999999999999999999; do
  if "$validator" 1.0.1 "$invalid" v1.0.1 >/dev/null 2>&1; then
    echo "expected invalid build '$invalid' to fail" >&2
    exit 1
  fi
done

# A tag must carry a release prefix, not merely be strippable of one (issue #4581).
for bad_tag in 1.2.0 release-1.2.0 v1.2.0-beta appstore-1.2.0 vv1.2.0; do
  if "$validator" 1.2.0 3000 "$bad_tag" >/dev/null 2>&1; then
    echo "expected tag '$bad_tag' to be rejected" >&2
    exit 1
  fi
done

# Marketing versions follow the same canonical component rule as bump-version.sh
# (issue #4582).
for bad_version in 01.2.0 1.002.0 1.0000000000.0 1234567890.1.0; do
  if "$validator" "$bad_version" 3000 >/dev/null 2>&1; then
    echo "expected marketing version '$bad_version' to be rejected" >&2
    exit 1
  fi
done

# Preserve build monotonicity across the historical project rename.
git mv PadBuddy.xcodeproj coderpad.xcodeproj
printf 'CURRENT_PROJECT_VERSION = 20000;\n' > coderpad.xcodeproj/project.pbxproj
git add coderpad.xcodeproj/project.pbxproj
git commit -qm 'historical project path'
git tag v1.0.1
if "$validator" 1.0.2 15000 v1.0.2 >output 2>&1; then
  echo "expected a build below the historical project build to fail" >&2
  exit 1
fi
grep -Fq "prior upload build '20000'" output
"$validator" 1.0.2 20001 v1.0.2 >/dev/null

# An unreadable project must still fail, rather than silently skipping a tag.
git rm -q coderpad.xcodeproj/project.pbxproj
git commit -qm 'missing project'
git tag v1.0.2
if "$validator" 1.0.3 20002 v1.0.3 >output 2>&1; then
  echo "expected a tag without either known project path to fail" >&2
  exit 1
fi
grep -Fq "could not read the project version at 'v1.0.2'" output

echo "Release-version validation tests passed."
