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

if [[ "$version" == *$'\n'* || -z "$version" ]]; then
  echo "error: version must be a non-empty single line" >&2
  exit 65
fi

if [[ ! "$release_url" =~ ^https://github\.com/[^/]+/[^/]+/releases/tag/[^/]+$ ]]; then
  echo "error: release URL must point to a GitHub release tag" >&2
  exit 65
fi

repository="${PACKAGE_ADOPTION_REPOSITORY:-adamtheturtle/coderpad-macos}"
title="Adopt $package_name $version"
body_file="$(mktemp)"
trap 'rm -f "$body_file"' EXIT

{
  echo "## Release"
  echo
  echo "$release_url"
  echo
  echo "## Upstream fixes included"
  echo
  if [[ $# -eq 0 ]]; then
    echo "- No individual upstream issues were supplied."
  else
    for issue_url in "$@"; do
      if [[ ! "$issue_url" =~ ^https://github\.com/[^/]+/[^/]+/issues/[0-9]+$ ]]; then
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

existing_url="$(
  gh issue list \
    --repo "$repository" \
    --state all \
    --search "$title in:title" \
    --limit 100 \
    --json title,url | \
    jq -r --arg wanted "$title" \
      'first(.[] | select(.title == $wanted) | .url) // empty'
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
