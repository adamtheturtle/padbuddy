#!/usr/bin/env bash
#
# Run SwiftLint's compiler-backed rules against the shipping app target.
#
# `unused_declaration` needs the complete module to understand cross-file
# references, so it must never be narrowed to changed files. `unused_import` is
# file-local and expensive; CI runs it only on Swift files changed by the current
# pull request or push. Set SWIFTLINT_ANALYZE_ALL_IMPORTS=1 for a deliberate full
# import audit.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <xcodebuild-compiler-log>" >&2
  exit 64
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compiler_log="$1"
if [[ "$compiler_log" != /* ]]; then
  compiler_log="$PWD/$compiler_log"
fi
swiftlint_bin="${SWIFTLINT_BIN:-swiftlint}"
parallel_jobs="${SWIFTLINT_ANALYZER_JOBS:-4}"
baseline="$repo_root/.swiftlint-analyzer-baseline.json"

cd "$repo_root"

if [[ ! -f "$compiler_log" ]]; then
  echo "error: SwiftLint compiler log does not exist: $compiler_log" >&2
  exit 66
fi

if [[ ! -f "$baseline" ]]; then
  echo "error: SwiftLint analyzer baseline does not exist: $baseline" >&2
  exit 66
fi

"$swiftlint_bin" analyze PadBuddy \
  --only-rule unused_declaration \
  --only-rule capture_variable \
  --only-rule typesafe_array_init \
  --baseline "$baseline" \
  --strict \
  --compiler-log-path "$compiler_log" \
  --reporter github-actions-logging \
  --quiet

changed_files="$(mktemp)"
trap 'rm -f "$changed_files"' EXIT

if [[ "${SWIFTLINT_ANALYZE_ALL_IMPORTS:-0}" == "1" ]]; then
  find PadBuddy -name '*.swift' -print0 > "$changed_files"
elif [[ -n "${SWIFTLINT_ANALYZER_DIFF_BASE:-}" ]] &&
    git rev-parse --verify "${SWIFTLINT_ANALYZER_DIFF_BASE}^{commit}" >/dev/null 2>&1; then
  while IFS= read -r -d '' source_file; do
    if [[ "$source_file" == *.swift && -f "$source_file" ]]; then
      printf '%s\0' "$source_file"
    fi
  done < <(
    git diff --name-only --diff-filter=ACMR -z \
      "$SWIFTLINT_ANALYZER_DIFF_BASE" HEAD -- PadBuddy
  ) > "$changed_files"
elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  while IFS= read -r -d '' source_file; do
    if [[ "$source_file" == *.swift && -f "$source_file" ]]; then
      printf '%s\0' "$source_file"
    fi
  done < <(git diff --name-only --diff-filter=ACMR -z HEAD^ HEAD -- PadBuddy) > "$changed_files"
else
  echo "warning: no parent commit is available; analyzing imports in every app source file" >&2
  find PadBuddy -name '*.swift' -print0 > "$changed_files"
fi

if [[ ! -s "$changed_files" ]]; then
  echo "SwiftLint unused-import analysis: no changed app Swift files"
  exit 0
fi

export SWIFTLINT_ANALYZER_BIN="$swiftlint_bin"
export SWIFTLINT_ANALYZER_COMPILER_LOG="$compiler_log"

# shellcheck disable=SC2016 # Variables expand in the nested bash process.
xargs -0 -n 1 -P "$parallel_jobs" bash -c '
  "$SWIFTLINT_ANALYZER_BIN" analyze "$1" \
    --only-rule unused_import \
    --strict \
    --compiler-log-path "$SWIFTLINT_ANALYZER_COMPILER_LOG" \
    --reporter github-actions-logging \
    --quiet
' _ < "$changed_files"
