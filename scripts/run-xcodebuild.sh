#!/usr/bin/env bash
#
# Keep complete xcodebuild output in a log while surfacing only useful summaries
# and failure diagnostics in the terminal or GitHub Actions console.
#
# For a test action the wrapper also requires that tests actually ran: xcodebuild exits
# successfully when a misspelled -only-testing selector or a test plan configuration
# selects nothing, which would let CI go green having run no regression tests
# (issue #4585). Set RUN_XCODEBUILD_ALLOW_ZERO_TESTS=1 for a run where selecting no tests
# is a legitimate outcome.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <log-path> <xcodebuild arguments...>" >&2
  exit 64
fi

log_path="$1"
shift
xcodebuild_bin="${XCODEBUILD_BIN:-xcodebuild}"
result_bundle=""
expect_result_bundle=0

is_test_action=0
previous_argument=""
for argument in "$@"; do
  if [[ "$expect_result_bundle" == "1" ]]; then
    result_bundle="$argument"
    expect_result_bundle=0
  elif [[ "$argument" == "-resultBundlePath" ]]; then
    expect_result_bundle=1
  fi
  # Actions are positional, so only a bare word that is not a flag's value counts.
  if [[ "$previous_argument" != -* ]]; then
    case "$argument" in
      test | test-without-building) is_test_action=1 ;;
    esac
  fi
  previous_argument="$argument"
done

if [[ -n "$result_bundle" && "$result_bundle" != /* ]]; then
  result_bundle="$PWD/$result_bundle"
fi

if [[ "$log_path" != /* ]]; then
  log_path="$PWD/$log_path"
fi

mkdir -p "$(dirname "$log_path")"
started_at="$SECONDS"

if "$xcodebuild_bin" "$@" > "$log_path" 2>&1; then
  echo "xcodebuild succeeded in $((SECONDS - started_at))s; full log: $log_path"
  sed -n '/Build Timing Summary/,$p' "$log_path" | tail -n 120
  grep -E 'Test session results|Executed [0-9]+ tests|\*\* (BUILD|TEST) SUCCEEDED \*\*' \
    "$log_path" | tail -n 20 || true
  if [[ -d "$result_bundle" ]] && command -v jq >/dev/null 2>&1; then
    # Best-effort, like the two grep summaries above. `get build-results metrics` is
    # a recent subcommand that is not on every Xcode this may be built with, and the
    # jq program errors outright when `.endTime`/`.startTime` are absent (`null -
    # null` is a type error). Under `set -e` either aborted the script before the
    # `exit 0` below, reporting a build that genuinely succeeded as a failure (#4790).
    if ! summary="$(xcrun xcresulttool get build-results metrics --path "$result_bundle" 2>/dev/null \
      | jq -r '"Result: \(.actionTitle // "build") — \(.status // "unknown") in "
        + "\((((.endTime // 0) - (.startTime // 0)) | floor))s, "
        + "\(.warningCount // 0) warnings, \(.errorCount // 0) errors"' 2>/dev/null)"; then
      summary=""
    fi
    if [[ -n "$summary" ]]; then
      echo "$summary"
    fi
  fi
  if [[ "$is_test_action" == "1" && "${RUN_XCODEBUILD_ALLOW_ZERO_TESTS:-0}" != "1" ]]; then
    executed="$(grep -cE "Test case '.*' (passed|failed) on " "$log_path" || true)"
    if [[ "$executed" == "0" ]]; then
      # XCTest's own summary, for runs whose per-case lines are not in the log.
      executed="$(grep -Eo 'Executed [0-9]+ test' "$log_path" | grep -Eo '[0-9]+' \
        | sort -n | tail -1 || true)"
      executed="${executed:-0}"
    fi
    if (( executed == 0 )); then
      echo "error: xcodebuild reported success but ran no tests; full log: $log_path" >&2
      echo "       check the -only-testing selectors and test plan, or set" >&2
      echo "       RUN_XCODEBUILD_ALLOW_ZERO_TESTS=1 if that is expected." >&2
      exit 1
    fi
    echo "Ran $executed test case(s)."
  fi
  exit 0
fi

echo "xcodebuild failed after $((SECONDS - started_at))s; full log: $log_path" >&2
if ! grep -n -E -B 2 -A 2 \
  '(^| )error:|fatal error:|Test case .* failed|Failing tests:|\*\* (BUILD|TEST) FAILED \*\*' \
  "$log_path" | tail -n 300 >&2; then
  tail -n 200 "$log_path" >&2
fi
exit 1
