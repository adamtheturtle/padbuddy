#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-xcode-version.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

stub_xcodebuild() {
  local version="$1"
  local build="$2"
  cat > "$fixture/xcodebuild" <<EOF
#!/usr/bin/env bash
echo "Xcode $version"
echo "Build version $build"
EOF
  chmod +x "$fixture/xcodebuild"
}

run_gate() {
  (
    cd "$fixture"
    PATH="$fixture:$PATH" "$checker"
  )
}

stub_xcodebuild 26.5 16F6
printf '26.5\n' > "$fixture/.xcode-version"
run_gate >/dev/null

printf '26.5\n16F6\n' > "$fixture/.xcode-version"
run_gate >/dev/null

printf '26. 5\n' > "$fixture/.xcode-version"
if run_gate >/dev/null 2>&1; then
  echo "expected internal whitespace in the version pin to fail" >&2
  exit 1
fi

printf '26.5\nbad build\n' > "$fixture/.xcode-version"
if run_gate >/dev/null 2>&1; then
  echo "expected internal whitespace in the build pin to fail" >&2
  exit 1
fi

printf '26.5\n16F6\n16F7\n' > "$fixture/.xcode-version"
if run_gate >/dev/null 2>&1; then
  echo "expected more than two pin lines to fail" >&2
  exit 1
fi

printf '26.5\n16F7\n' > "$fixture/.xcode-version"
if run_gate >/dev/null 2>&1; then
  echo "expected a mismatched build pin to fail" >&2
  exit 1
fi

echo "Xcode version gate tests passed."
