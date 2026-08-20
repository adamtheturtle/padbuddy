#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/create-package-adoption-issue.sh"

assert_fails() {
  local label="$1"
  shift
  if "$script" --dry-run "$@" >/dev/null 2>&1; then
    echo "expected failure: $label" >&2
    exit 1
  fi
}

assert_fails "carriage-return version" Package $'1.0\r' "https://github.com/acme/pkg/releases/tag/1.0"
# shellcheck disable=SC2016 # intentional literal backticks in the rejected version
assert_fails "markdown version" Package '1.0*`oops`' "https://github.com/acme/pkg/releases/tag/1.0"
assert_fails "whitespace version" Package ' 1.0 ' "https://github.com/acme/pkg/releases/tag/1.0"
assert_fails "query release URL" Package 1.0 "https://github.com/acme/pkg/releases/tag/1.0?x=1"
assert_fails "fragment release URL" Package 1.0 "https://github.com/acme/pkg/releases/tag/1.0#frag"
assert_fails "http release URL" Package 1.0 "http://github.com/acme/pkg/releases/tag/1.0"
assert_fails "space in tag" Package 1.0 "https://github.com/acme/pkg/releases/tag/1 0"

output="$("$script" --dry-run Package 1.2.3 "https://github.com/acme/pkg/releases/tag/v1.2.3")"
grep -Fq 'Title: Adopt Package 1.2.3' <<<"$output"
grep -Fq '<!-- padbuddy-package-adoption:Package:1.2.3 -->' <<<"$output"
grep -Fq 'https://github.com/acme/pkg/releases/tag/v1.2.3' <<<"$output"

echo "Package adoption issue validation tests passed."
