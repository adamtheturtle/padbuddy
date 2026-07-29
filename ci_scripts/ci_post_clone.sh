#!/bin/sh

# Xcode Cloud runs this immediately after cloning the repository, before
# resolving dependencies or building. It is the most common customization hook.
#
# SwiftPM resolves the private buddy-kit repository. Xcode Cloud must provide a
# secret BUDDY_KIT_TOKEN with read-only Contents access to that repository.
#
# Notes:
#   - Runs from $CI_PRIMARY_REPOSITORY_PATH/ci_scripts.
#   - Must exit 0 to let the build proceed.
#   - Keep it idempotent; it runs on every build.

set -e

if [ -z "${BUDDY_KIT_TOKEN:-}" ]; then
  echo "error: BUDDY_KIT_TOKEN is required to resolve the private buddy-kit Swift package." >&2
  exit 1
fi

git config --global \
  url."https://x-access-token:${BUDDY_KIT_TOKEN}@github.com/adamtheturtle/buddy-kit".insteadOf \
  "https://github.com/adamtheturtle/buddy-kit"
git ls-remote https://github.com/adamtheturtle/buddy-kit HEAD >/dev/null
echo "ci_post_clone: private Swift package access verified."
