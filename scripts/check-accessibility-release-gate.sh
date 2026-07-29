#!/usr/bin/env bash
#
# Ensure a release has a fresh, completed Accessibility Inspector audit recorded.
# Usage: scripts/check-accessibility-release-gate.sh [base-ref]

set -euo pipefail

audit_doc="docs/cross-cutting-quality-audit.md"
base_ref="${1:-}"

if [[ ! -f "$audit_doc" ]]; then
  echo "error: accessibility audit document not found at $audit_doc" >&2
  exit 1
fi

if ! grep -Eq '^## Accessibility — completed [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$audit_doc"; then
  echo "error: $audit_doc must record a completed accessibility audit date." >&2
  exit 1
fi

if grep -Eiq '(^|[^[:alnum:]])P[01]([^[:alnum:]].*(open|unresolved|fail|failing|todo|needs)|.*\[[[:space:]]\])' "$audit_doc"; then
  echo "error: $audit_doc records unresolved P0/P1 accessibility findings." >&2
  exit 1
fi

if [[ -z "$base_ref" ]]; then
  while IFS= read -r tag; do
    [[ -n "$tag" ]] || continue
    if [[ "$(git rev-parse "$tag^{commit}")" != "$(git rev-parse HEAD)" ]]; then
      base_ref="$tag"
      break
    fi
  done < <(git tag --merged HEAD --sort=-creatordate --list 'v*' 'appstore-v*')
fi

if [[ -n "$base_ref" ]] && git diff --quiet "$base_ref"..HEAD -- "$audit_doc"; then
  echo "error: $audit_doc has not changed since $base_ref." >&2
  echo "Run Accessibility Inspector on critical screens and record the completed audit before releasing." >&2
  exit 1
fi

echo "Accessibility release gate OK: $audit_doc is completed and fresh."
