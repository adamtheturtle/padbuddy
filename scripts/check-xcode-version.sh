#!/usr/bin/env bash

set -euo pipefail

required="$(tr -d '[:space:]' < .xcode-version)"
actual="$(xcodebuild -version | sed -nE 's/^Xcode ([^[:space:]]+).*$/\1/p' | head -1)"

if [[ "$actual" != "$required" ]]; then
  echo "error: PadBuddy requires Xcode $required; active xcodebuild is ${actual:-unknown}." >&2
  echo "Set DEVELOPER_DIR to the Xcode $required Developer directory before building or testing." >&2
  exit 1
fi

echo "Xcode version gate passed: $actual."
