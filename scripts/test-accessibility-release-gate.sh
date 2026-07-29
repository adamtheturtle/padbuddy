#!/usr/bin/env bash

set -euo pipefail

fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT

assert_rejected() {
  local body="$1"
  printf '%s\n' "$body" > "$fixture"
  if ACCESSIBILITY_AUDIT_DOC="$fixture" scripts/check-accessibility-release-gate.sh 2>/dev/null; then
    echo "error: accessibility gate accepted an unresolved high-priority fixture." >&2
    exit 1
  fi
}

assert_rejected $'# Audit\n\n## Accessibility — completed 2026-07-20\n\n### P0 — Login controls\n\nStatus: Open'
assert_rejected $'# Audit\n\n## Accessibility — completed 2026-07-20\n\n### P1 — Focus order\n\n**Status:** Needs verification'

echo "Accessibility release gate adversarial tests passed."
