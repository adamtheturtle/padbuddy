#!/bin/sh

# Xcode Cloud runs this right before each xcodebuild action (build / test /
# archive). Use it for last-mile setup that must happen after dependency
# resolution but before compilation.
#
# Nothing is needed today. Left as a documented placeholder so the workflow
# is easy to extend later (e.g. stamping a build number from $CI_BUILD_NUMBER,
# or injecting an environment-specific value).

set -e

echo "ci_pre_xcodebuild: nothing to do."
