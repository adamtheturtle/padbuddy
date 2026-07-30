#!/usr/bin/env bash
#
# Generate a signed Sparkle appcast.xml for an in-app-update release (#28), so
# already-installed copies can discover and verify the new version.
#
# Usage:
#   scripts/generate-appcast.sh <tag> [<update-archive>]
#
# <tag> is the release tag (e.g. v1.2.3). <update-archive> defaults to the
# padbuddy-<tag>.dmg / .zip produced earlier in the release workflow.
#
# Required environment:
#   SPARKLE_PRIVATE_ED_KEY   The EdDSA private key string printed by Sparkle's
#                            `generate_keys -x` (store it as a repo secret). Used
#                            to sign the update; the matching public key lives in
#                            Info.plist's SUPublicEDKey.
#
# Optional environment:
#   SPARKLE_VERSION       Sparkle release whose `generate_appcast` tool to fetch.
#                         Defaults to the version resolved for the app.
#   GITHUB_SERVER_URL     GitHub base URL (default https://github.com).
#   RELEASES_REPOSITORY   owner/repo whose Releases host the DMG the appcast points
#                         at — the PUBLIC artifacts repo, since the app fetches the
#                         enclosure unauthenticated (default
#                         adamtheturtle/coderpad-macos-releases). This is NOT the
#                         private source repo.
#
# Writes appcast.xml to the current directory. The downloaded Sparkle tool
# archive is checked against a checksum pinned in this source file before it is
# extracted or given access to the signing key.
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

TAG="${1:-}"
[ -n "$TAG" ] || die "usage: $0 <tag> [<update-archive>]"

ARCHIVE="${2:-}"
if [ -z "$ARCHIVE" ]; then
    for candidate in "padbuddy-${TAG}.dmg" "padbuddy-${TAG}.zip"; do
        [ -f "$candidate" ] && ARCHIVE="$candidate" && break
    done
fi
if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
    die "update archive not found for $TAG"
fi

: "${SPARKLE_PRIVATE_ED_KEY:?set SPARKLE_PRIVATE_ED_KEY (Sparkle EdDSA private key)}"

PACKAGE_RESOLVED="coderpad.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
RESOLVED_SPARKLE_VERSION="$(jq -er \
    '.pins[] | select(.identity == "sparkle") | .state.version' \
    "$PACKAGE_RESOLVED")" || die "could not resolve Sparkle version from $PACKAGE_RESOLVED"
SPARKLE_VERSION="${SPARKLE_VERSION:-$RESOLVED_SPARKLE_VERSION}"
case "$SPARKLE_VERSION" in
    2.9.3)
        SPARKLE_ARCHIVE_SHA256="74a07da821f92b79310009954c0e15f350173374a3abe39095b4fc5096916be6"
        ;;
    *)
        die "no trusted archive checksum pinned for Sparkle $SPARKLE_VERSION"
        ;;
esac
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
# Enclosure URLs must point at the PUBLIC artifacts repo (the app downloads them
# unauthenticated), not the private source repo.
RELEASES_REPOSITORY="${RELEASES_REPOSITORY:-adamtheturtle/coderpad-macos-releases}"
DOWNLOAD_PREFIX="${SERVER_URL}/${RELEASES_REPOSITORY}/releases/download/${TAG}/"

WORK="$(mktemp -d)"
KEY_FILE="$WORK/sparkle_ed_private_key"
ARCHIVES_DIR="$WORK/archives"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Fetch Sparkle's prebuilt tools, verify the release asset against the digest
# published by the Sparkle project, and only then extract it.
echo "Fetching Sparkle $SPARKLE_VERSION tools…"
curl -fsSL \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    -o "$WORK/sparkle.tar.xz"
ACTUAL_SHA256="$(shasum -a 256 "$WORK/sparkle.tar.xz" | awk '{print $1}')"
[ "$ACTUAL_SHA256" = "$SPARKLE_ARCHIVE_SHA256" ] \
    || die "Sparkle archive checksum mismatch (expected $SPARKLE_ARCHIVE_SHA256, got $ACTUAL_SHA256)"
tar -xJf "$WORK/sparkle.tar.xz" -C "$WORK"
GENERATE_APPCAST="$WORK/bin/generate_appcast"
[ -x "$GENERATE_APPCAST" ] || die "generate_appcast not found in Sparkle archive"

# Do not put the private key on disk until all network-supplied code has passed
# verification and extraction. Restrict the file before writing the secret.
( umask 077 && printf '%s' "$SPARKLE_PRIVATE_ED_KEY" > "$KEY_FILE" )

# generate_appcast scans a directory of update archives; give it just this build.
mkdir -p "$ARCHIVES_DIR"
cp "$ARCHIVE" "$ARCHIVES_DIR/"

echo "Generating appcast for $ARCHIVE (download prefix: $DOWNLOAD_PREFIX)…"
"$GENERATE_APPCAST" \
    --ed-key-file "$KEY_FILE" \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    "$ARCHIVES_DIR"

cp "$ARCHIVES_DIR/appcast.xml" ./appcast.xml
echo "Wrote appcast.xml"
