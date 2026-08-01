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
mkdir coderpad.xcodeproj
printf 'CURRENT_PROJECT_VERSION = 10000;\n' > coderpad.xcodeproj/project.pbxproj
git add coderpad.xcodeproj/project.pbxproj
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

echo "Release-version validation tests passed."
