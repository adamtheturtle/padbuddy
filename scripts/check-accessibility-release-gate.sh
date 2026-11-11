#!/usr/bin/env bash
#
# Ensure a release has a fresh, completed Accessibility Inspector audit recorded.
# Usage: scripts/check-accessibility-release-gate.sh [base-ref]

set -euo pipefail

audit_doc="${ACCESSIBILITY_AUDIT_DOC:-docs/cross-cutting-quality-audit.md}"
base_ref="${1:-}"

if [[ ! -f "$audit_doc" ]]; then
  echo "error: accessibility audit document not found at $audit_doc" >&2
  exit 1
fi

if ! grep -Eq '^## Accessibility — completed [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$audit_doc"; then
  echo "error: $audit_doc must record a completed accessibility audit date." >&2
  exit 1
fi
audit_date="$(sed -nE 's/^## Accessibility — completed ([0-9]{4}-[0-9]{2}-[0-9]{2})$/\1/p' "$audit_doc")"
if ! parsed_audit_date="$(date -j -f '%Y-%m-%d' "$audit_date" '+%Y-%m-%d' 2>/dev/null)" ||
   [[ "$parsed_audit_date" != "$audit_date" ]]; then
  echo "error: accessibility audit date '$audit_date' is not a valid calendar date." >&2
  exit 1
fi
today="$(date -u '+%Y-%m-%d')"
if [[ "$audit_date" > "$today" ]]; then
  echo "error: accessibility audit date '$audit_date' is in the future." >&2
  exit 1
fi

if grep -Eiq '(^|[^[:alnum:]])P[01]([^[:alnum:]].*(open|unresolved|fail|failing|todo|needs)|.*\[[[:space:]]\])' "$audit_doc" ||
   awk '
     BEGIN { in_high_priority_finding = 0; unresolved = 0 }
     /^#{1,6}[[:space:]]/ {
       heading = tolower($0)
       in_high_priority_finding = (heading ~ /(^|[^[:alnum:]])p[01]([^[:alnum:]]|$)/)
       next
     }
     in_high_priority_finding {
       line = tolower($0)
       if (line ~ /status[^[:alnum:]]*(open|unresolved|fail|failing|todo|needs)/ ||
           line ~ /\[[[:space:]]\]/) {
         unresolved = 1
       }
     }
     END { exit unresolved ? 0 : 1 }
   ' "$audit_doc"; then
  echo "error: $audit_doc records unresolved P0/P1 accessibility findings." >&2
  exit 1
fi

# The nearest release tag reachable from HEAD, by history rather than by when the tag
# object happened to be written. Sorting by creator date let an annotated tag created (or
# recreated) later for an OLDER commit sort first, so the gate compared the audit against
# an earlier release and accepted an audit that predates the actual latest one
# (issue #4586). `git describe` answers the topological question directly.
if [[ -z "$base_ref" ]]; then
  probe="HEAD"
  head_commit="$(git rev-parse HEAD)"
  # Bounded so a tag chain that never leaves HEAD's commit cannot loop forever.
  for _ in $(seq 1 100); do
    candidate="$(git describe --tags --abbrev=0 \
      --match 'v*' --match 'appstore-v*' "$probe" 2>/dev/null || true)"
    [[ -n "$candidate" ]] || break

    if [[ "$(git rev-parse "$candidate^{commit}")" != "$head_commit" ]]; then
      base_ref="$candidate"
      break
    fi
    # This tag names HEAD itself — the release being cut — so look behind it.
    probe="$candidate^"
    git rev-parse --verify --quiet "$probe" >/dev/null || break
  done
fi

if [[ -n "$base_ref" ]]; then
  base_date="$(git log -1 --format=%cs "$base_ref^{commit}")"
  # Multiple releases can be cut on one day. The changed-record check below still
  # requires an audit update after the baseline; the date must not predate it.
  if [[ "$audit_date" < "$base_date" ]]; then
    echo "error: accessibility audit date $audit_date predates $base_ref ($base_date)." >&2
    exit 1
  fi
fi

if [[ -n "$base_ref" ]] && git diff --quiet "$base_ref"..HEAD -- "$audit_doc"; then
  echo "error: $audit_doc has not changed since $base_ref." >&2
  echo "Run Accessibility Inspector on critical screens and record the completed audit before releasing." >&2
  exit 1
fi

echo "Accessibility release gate OK: $audit_doc is completed and fresh."
