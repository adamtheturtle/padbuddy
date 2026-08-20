#!/usr/bin/env bash
#
# Create one downstream adoption tracker for an upstream package release.
# Individual bugs stay in the package repository and are linked as a checklist.

set -euo pipefail

dry_run=0
if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=1
  shift
fi

if [[ $# -lt 3 ]]; then
  echo "usage: $0 [--dry-run] <package> <version> <release-url> [upstream-issue-url ...]" >&2
  exit 64
fi

package_name="$1"
version="$2"
release_url="$3"
shift 3

if [[ ! "$package_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "error: package names may contain only letters, numbers, dot, underscore, and hyphen" >&2
  exit 65
fi

# Reject empty, whitespace-padded, control, and Markdown-significant characters so
# the title/search query cannot be spoofed by release automation inputs (#4629).
if [[ ! "$version" =~ ^[A-Za-z0-9]([A-Za-z0-9._+-]*[A-Za-z0-9])?$ ]]; then
  echo "error: version must be a non-empty release token without whitespace or controls" >&2
  exit 65
fi

canonical_release_url="$(
  python3 - "$release_url" <<'PY'
import sys
from urllib.parse import urlparse

raw = sys.argv[1]
parsed = urlparse(raw)
if parsed.scheme != "https" or parsed.netloc.lower() != "github.com":
    raise SystemExit(1)
if parsed.username or parsed.password or parsed.query or parsed.fragment:
    raise SystemExit(1)
parts = [part for part in parsed.path.split("/") if part]
if len(parts) != 5 or parts[2:4] != ["releases", "tag"]:
    raise SystemExit(1)
owner, repo, _, _, tag = parts
for label, value in (("owner", owner), ("repo", repo), ("tag", tag)):
    if any(ch in value for ch in " \t\r\n?#%") or not value:
        raise SystemExit(1)
    if label in {"owner", "repo"} and not all(ch.isalnum() or ch in "._-" for ch in value):
        raise SystemExit(1)
print(f"https://github.com/{owner}/{repo}/releases/tag/{tag}")
PY
)" || {
  echo "error: release URL must be a canonical https://github.com/<owner>/<repo>/releases/tag/<tag>" >&2
  exit 65
}

repository="${PACKAGE_ADOPTION_REPOSITORY:-adamtheturtle/padbuddy}"
# Stable machine-readable marker for exact duplicate detection beyond search-page limits (#4630).
adoption_key="padbuddy-package-adoption:$package_name:$version"
title="Adopt $package_name $version"
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

{
  echo "<!-- $adoption_key -->"
  echo "## Release"
  echo
  echo "$canonical_release_url"
  echo
  echo "## Upstream fixes included"
  echo
  if [[ $# -eq 0 ]]; then
    echo "- No individual upstream issues were supplied."
  else
    for issue_url in "$@"; do
      if [[ ! "$issue_url" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/issues/[0-9]+$ ]]; then
        echo "error: invalid upstream issue URL: $issue_url" >&2
        exit 65
      fi
      printf -- '- [ ] %s\n' "$issue_url"
    done
  fi
  echo
  echo "## Downstream adoption"
  echo
  echo "- [ ] Update the Xcode package requirement and Package.resolved."
  echo "- [ ] Run ./scripts/preflight.sh."
  echo "- [ ] Confirm any app-side migration or compatibility work."
} > "$body_file"

if [[ "$dry_run" == "1" ]]; then
  printf 'Title: %s\n\n' "$title"
  cat "$body_file"
  exit 0
fi

for command_name in gh jq; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: $command_name is required to create the adoption issue" >&2
    exit 69
  fi
done

# Exact body-marker search is deterministic and is not capped by fuzzy title ranking (#4630).
existing_url="$(
  gh issue list \
    --repo "$repository" \
    --state all \
    --search "\"$adoption_key\" in:body" \
    --limit 100 \
    --json title,url,body | \
    jq -r --arg key "$adoption_key" --arg wanted "$title" \
      'first(.[] | select((.body // "") | contains($key)) | select(.title == $wanted) | .url) // empty'
)"

if [[ -n "$existing_url" ]]; then
  echo "Adoption tracker already exists: $existing_url"
  exit 0
fi

gh issue create \
  --repo "$repository" \
  --title "$title" \
  --label dependencies \
  --body-file "$body_file"
