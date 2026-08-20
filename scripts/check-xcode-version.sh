#!/usr/bin/env bash

set -euo pipefail

# Read exactly one trimmed marketing-version line. Deleting *all* whitespace used to
# turn corrupt pins like `26. 5` into `26.5` and let them pass (#4627). An optional
# second line may pin the Xcode build identifier (#4628).
nonempty=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  trimmed="${line#"${line%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -n "$trimmed" ]] || continue
  nonempty+=("$trimmed")
done < .xcode-version

if ((${#nonempty[@]} < 1 || ${#nonempty[@]} > 2)); then
  echo "error: .xcode-version must contain one version line and an optional build line." >&2
  exit 1
fi

required="${nonempty[0]}"
required_build=""
if ((${#nonempty[@]} == 2)); then
  required_build="${nonempty[1]}"
fi
if [[ "$required" =~ [[:space:]] ]]; then
  echo "error: Xcode version pin '$required' must not contain internal whitespace." >&2
  exit 1
fi
if [[ -n "$required_build" && "$required_build" =~ [[:space:]] ]]; then
  echo "error: Xcode build pin '$required_build' must not contain internal whitespace." >&2
  exit 1
fi

xcode_version_output="$(xcodebuild -version)"
actual="$(printf '%s\n' "$xcode_version_output" | sed -nE 's/^Xcode ([^[:space:]]+).*$/\1/p' | head -1)"
actual_build="$(printf '%s\n' "$xcode_version_output" | sed -nE 's/^Build version ([^[:space:]]+).*$/\1/p' | head -1)"

if [[ "$actual" != "$required" ]]; then
  echo "error: PadBuddy requires Xcode $required; active xcodebuild is ${actual:-unknown}." >&2
  echo "Set DEVELOPER_DIR to the Xcode $required Developer directory before building or testing." >&2
  exit 1
fi

if [[ -n "$required_build" && "$actual_build" != "$required_build" ]]; then
  echo "error: PadBuddy requires Xcode build $required_build; active xcodebuild is ${actual_build:-unknown}." >&2
  echo "Set DEVELOPER_DIR to the matching Xcode $required ($required_build) Developer directory." >&2
  exit 1
fi

if [[ -n "$required_build" ]]; then
  echo "Xcode version gate passed: $actual ($actual_build)."
else
  echo "Xcode version gate passed: $actual."
fi
