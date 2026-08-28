#!/usr/bin/env bash
#
# Fail if an App Store archive contains Sparkle anywhere.
#
# The App Store build must ship no updater (#483). Checking only the app bundle's own
# `Frameworks` directory let a copy embedded in an appex, helper app, or XPC service pass
# validation, and a linked-but-not-embedded reference pass with no framework at all
# (#4623). This looks through the whole archive — every nested bundle — and at what the
# Mach-O binaries actually link and load.

set -euo pipefail

archive="${1:-}"
if [[ -z "$archive" || ! -d "$archive" ]]; then
  echo "usage: $(basename "$0") <path-to-.xcarchive>" >&2
  exit 64
fi

failed=0

# Any Sparkle bundle, at any depth: Contents/Frameworks, a widget's PlugIns, an XPC
# service inside a framework, anywhere.
while IFS= read -r hit; do
  echo "::error::Sparkle is embedded in the App Store archive at ${hit#"$archive"/}"
  failed=1
done < <(find "$archive" \( -name 'Sparkle.framework' -o -name 'Sparkle' -type d \
  -o -name 'Autoupdate' -o -name 'Updater.app' \) -print)

# A binary can reference Sparkle without embedding it, which fails review just the same.
while IFS= read -r binary; do
  file "$binary" | grep -q 'Mach-O' || continue

  if otool -L "$binary" 2>/dev/null | grep -qi 'sparkle'; then
    echo "::error::${binary#"$archive"/} links against Sparkle"
    failed=1
  fi
done < <(find "$archive" -type f -perm -111)

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi

echo "OK: no Sparkle framework, helper, or linkage anywhere in $archive."
