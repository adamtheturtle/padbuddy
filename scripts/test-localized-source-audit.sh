#!/usr/bin/env bash
set -euo pipefail

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT
mkdir -p "$fixture_root/coderpad"

cp scripts/check-localized-source.swift "$fixture_root/check.swift"
printf '%s\n' '{"sourceLanguage":"en","strings":{"Catalogued":{"localizations":{}}},"version":"1.0"}' \
  > "$fixture_root/coderpad/Localizable.xcstrings"
printf '%s\n' 'import SwiftUI' 'struct Fixture: View {' \
  'var statusMessage: String { "Missing status" }' \
  'var body: some View { VStack { Text("Catalogued"); Button("Missing") {} }.accessibilityHint("Missing hint") }' '}' \
  > "$fixture_root/coderpad/Fixture.swift"
printf '%s\n' '[]' > "$fixture_root/.localization-source-allowlist.json"

if swift "$fixture_root/check.swift" "$fixture_root" > "$fixture_root/output" 2>&1; then
  echo 'error: source audit accepted an uncatalogued Button literal.' >&2
  exit 1
fi
grep -q 'Missing' "$fixture_root/output"
grep -q 'Missing status' "$fixture_root/output"
grep -q 'Missing hint' "$fixture_root/output"

printf '%s\n' \
  '[{"path":"coderpad/Fixture.swift","value":"Missing","reason":"Intentional fixture exemption"},' \
  ' {"path":"coderpad/Fixture.swift","value":"Missing status","reason":"Intentional fixture exemption"},' \
  ' {"path":"coderpad/Fixture.swift","value":"Missing hint","reason":"Intentional fixture exemption"}]' \
  > "$fixture_root/.localization-source-allowlist.json"
swift "$fixture_root/check.swift" "$fixture_root"

printf '%s\n' \
  '[{"path":"coderpad/Fixture.swift","value":"Missing","reason":""}]' \
  > "$fixture_root/.localization-source-allowlist.json"
if swift "$fixture_root/check.swift" "$fixture_root" >/dev/null 2>&1; then
  echo 'error: source audit accepted an allowlist entry without a reason.' >&2
  exit 1
fi

echo 'Localized source audit adversarial fixtures passed.'
