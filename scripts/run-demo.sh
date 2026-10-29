#!/usr/bin/env bash
# Build and launch a fresh macOS demo instance for visual checks.
# Extra arguments go to the app, for example -uiTestingNoAccounts.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${DEMO_DERIVED_DATA_PATH:-$repo_root/.context/DerivedData-demo}"
case "$derived_data" in
  /*) ;;
  *) derived_data="$repo_root/$derived_data" ;;
esac

"$repo_root/scripts/build-fast.sh" -derivedDataPath "$derived_data"

demo_app="$derived_data/Build/Products/Debug/PadBuddy.app"
echo "Launching demo (PID $$): $demo_app"

# A new instance is essential: an existing personal session would ignore the
# launch arguments and continue using its real accounts.
exec "$demo_app/Contents/MacOS/PadBuddy" \
  -ApplePersistenceIgnoreState YES \
  -uiTesting \
  -uiTestingKeepDefaultWindowSize \
  "$@"
