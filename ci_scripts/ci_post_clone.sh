#!/bin/sh

# Xcode Cloud runs this immediately after cloning the repository, before
# resolving dependencies or building. It is the most common customization hook.
#
# This project currently has no external dependencies (no SPM/CocoaPods/Carthage)
# and no code generation, so there is nothing required here yet — Xcode Cloud
# builds the `coderpad` scheme out of the box.
#
# Add setup steps here if that changes, e.g.:
#   - Installing a tool:        brew install swiftlint
#   - Writing a generated file: ./Scripts/generate-config.sh
#   - Restoring secrets:        printf '%s' "$SOME_SECRET" > Config.xcconfig
#     (define SOME_SECRET as an environment variable in the Xcode Cloud workflow)
#
# Notes:
#   - Runs from $CI_PRIMARY_REPOSITORY_PATH/ci_scripts.
#   - Must exit 0 to let the build proceed.
#   - Keep it idempotent; it runs on every build.

set -e

echo "ci_post_clone: no setup required for coderpad."
