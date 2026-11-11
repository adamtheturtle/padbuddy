#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp)"
baseline_repo="$(mktemp -d)"
trap 'rm -f "$fixture"; rm -rf "$baseline_repo"' EXIT

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
assert_rejected $'# Audit\n\n## Accessibility — completed 2026-07-20\n\n### p0 — Login controls\n\nStatus: Open'
assert_rejected $'# Audit\n\n## Accessibility — completed 2026-07-20\n\n### p1 — Focus order\n\n**Status:** Needs verification'
assert_rejected $'# Audit\n\n## Accessibility — completed 2026-02-30\n\nAll clear.'
assert_rejected $'# Audit\n\n## Accessibility — completed 2099-01-01\n\nAll clear.'

# The baseline must be the nearest release in history, not whichever tag object was
# written most recently (issue #4586).
(
  cd "$baseline_repo"
  git init -q
  git config user.email test@example.com
  git config user.name Test
  git config commit.gpgsign false
  git config tag.gpgsign false
  cp -R "$repo_root/scripts" scripts
  mkdir -p docs

  write_audit() {
    printf '# Audit\n\n## Accessibility — completed %s\n\nAll clear.\n' "$1" \
      > docs/cross-cutting-quality-audit.md
  }

  write_audit 2026-01-01
  git add -A
  GIT_COMMITTER_DATE='2026-01-01T00:00:00Z' git commit -qm old --date='2026-01-01T00:00:00Z'
  git tag v1.0.0

  write_audit 2026-02-01
  git add -A
  GIT_COMMITTER_DATE='2026-06-01T00:00:00Z' git commit -qm newer --date='2026-06-01T00:00:00Z'
  # Tagged AFTER v1.0.0 in wall-clock terms but naming the newer commit, then an
  # annotated tag re-created for the OLDER commit, which sorts first by creator date.
  git tag v2.0.0
  git tag -a -m recreated v0.9.0 "v1.0.0^{commit}"

  write_audit 2026-03-01
  git add -A
  GIT_COMMITTER_DATE='2026-06-20T00:00:00Z' git commit -qm release --date='2026-06-20T00:00:00Z'

  # The audit (2026-03-01) is newer than v1.0.0/v0.9.0 (2026-01-01) but older than the
  # real latest release v2.0.0 (2026-06-01). Picking the most recently *created* tag
  # accepted this stale audit; picking the nearest one in history must not.
  if scripts/check-accessibility-release-gate.sh >/dev/null 2>&1; then
    echo "error: accessibility gate used an older tag as its baseline." >&2
    exit 1
  fi

  # A fresh record on the same calendar day as the baseline is valid. Requiring a
  # strictly newer date prevents all same-day follow-up releases, including a
  # packaging retry after a failed tag build.
  write_audit 2026-06-01
  git add -A
  GIT_COMMITTER_DATE='2026-06-21T00:00:00Z' git commit -qm refreshed --date='2026-06-21T00:00:00Z'
  git tag v2.0.1

  write_audit 2026-06-21
  git add -A
  GIT_COMMITTER_DATE='2026-06-21T01:00:00Z' git commit -qm same-day-audit --date='2026-06-21T01:00:00Z'
  scripts/check-accessibility-release-gate.sh >/dev/null
  git tag v2.0.2

  # A same-day date alone cannot reuse the previous release's unchanged record.
  GIT_COMMITTER_DATE='2026-06-21T02:00:00Z' git commit --allow-empty -qm unchanged --date='2026-06-21T02:00:00Z'
  if scripts/check-accessibility-release-gate.sh >/dev/null 2>&1; then
    echo "error: accessibility gate accepted an unchanged same-day audit." >&2
    exit 1
  fi
)

echo "Accessibility release gate adversarial tests passed."
