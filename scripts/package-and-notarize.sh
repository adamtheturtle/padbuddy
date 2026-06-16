#!/usr/bin/env bash
#
# Sign (Developer ID), package as a .dmg, notarize, and staple a macOS .app so
# it opens cleanly on other people's Macs — no Gatekeeper "app is damaged /
# Apple cannot check it for malicious software" warning — when distributed
# directly (outside the Mac App Store).
#
# Usage:
#   scripts/package-and-notarize.sh <path-to-.app> [<output-dmg-path>]
#
# If <output-dmg-path> is omitted the .dmg is written next to the .app.
#
# Required environment:
#   SIGNING_IDENTITY   Codesign identity, e.g.
#                      "Developer ID Application: Your Name (TEAMID)". The
#                      matching certificate + private key must be in a keychain
#                      that is unlocked and on the search list.
#
# Notarization credentials — supply EITHER a stored profile:
#   NOTARY_KEYCHAIN_PROFILE   A `notarytool store-credentials` profile name.
# OR an Apple ID + app-specific password:
#   NOTARY_APPLE_ID    Apple ID email used for notarytool.
#   NOTARY_PASSWORD    App-specific password for that Apple ID.
#   NOTARY_TEAM_ID     Apple Developer Team ID (e.g. 6L9H6Q8CUF).
#
# Optional environment:
#   ENTITLEMENTS         Entitlements plist embedded when signing the app
#                        (default: coderpad/coderpad.entitlements, repo-relative).
#   WIDGET_ENTITLEMENTS  Entitlements plist embedded when signing the embedded
#                        widget extension (.appex)
#                        (default: RecentPadsWidgetExtension.entitlements).
#   VOLUME_NAME          Mounted-volume name for the .dmg (default: app name).
#
# The script signs nested code first (inside-out), then the app, with Hardened
# Runtime and a secure timestamp; builds a compressed .dmg with an /Applications
# drop target; signs, notarizes, and staples the .dmg; then validates it.
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

APP="${1:-}"
[ -n "$APP" ] || die "usage: $0 <path-to-.app> [<output-dmg-path>]"
[ -d "$APP" ] || die "no such .app: $APP"
APP="${APP%/}"

: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY (the Developer ID Application identity)}"

# Resolve the entitlements plist relative to the repo root (the dir above this
# script), so the script works regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTITLEMENTS="${ENTITLEMENTS:-$REPO_ROOT/coderpad/coderpad.entitlements}"
[ -f "$ENTITLEMENTS" ] || die "entitlements not found: $ENTITLEMENTS"

# Embedded app extensions (.appex) carry their own entitlements (the widget's
# app-group) and must be re-signed with them — a plain re-sign would strip them.
WIDGET_ENTITLEMENTS="${WIDGET_ENTITLEMENTS:-$REPO_ROOT/RecentPadsWidgetExtension.entitlements}"

APP_NAME="$(basename "$APP" .app)"
DMG="${2:-${APP%.app}.dmg}"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"

# --- Code signing -----------------------------------------------------------
# Sign with Hardened Runtime (--options runtime) and a secure timestamp; both
# are required for notarization. Sign nested code inside-out before the app, as
# Apple recommends over a single `--deep` pass.
sign() {
  codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$@"
}

echo "==> Signing nested code in $APP"
# Frameworks, dylibs, and any embedded helper executables, deepest path first.
while IFS= read -r -d '' nested; do
  echo "    sign: ${nested#"$APP"/}"
  sign "$nested"
done < <(
  find "$APP/Contents" \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \) \
    -print0 | sort -rz
)

# App extensions (.appex) come after the frameworks/dylibs nested inside them
# (signed above, deepest-first) but before the outer app. Each must be
# Developer-ID signed with Hardened Runtime + a timestamp AND keep its own
# entitlements; a plain re-sign would drop the widget's app-group. The outer
# `codesign "$APP"` below does NOT re-sign nested .appex bundles, and
# `codesign --verify` passes on an ad-hoc-signed appex — so a missed appex only
# surfaces when the notary service rejects it.
while IFS= read -r -d '' appex; do
  echo "    sign appex: ${appex#"$APP"/}"
  if [ -f "$WIDGET_ENTITLEMENTS" ]; then
    sign --entitlements "$WIDGET_ENTITLEMENTS" "$appex"
  else
    sign "$appex"
  fi
done < <(find "$APP/Contents" -name '*.appex' -print0 | sort -rz)

echo "==> Signing app bundle (entitlements: ${ENTITLEMENTS#"$REPO_ROOT"/})"
sign --entitlements "$ENTITLEMENTS" "$APP"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- Package as .dmg --------------------------------------------------------
echo "==> Building $DMG"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target
rm -f "$DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"

echo "==> Signing $DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

# --- Notarize + staple ------------------------------------------------------
notarytool_creds=()
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  notarytool_creds=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else
  : "${NOTARY_APPLE_ID:?set NOTARY_APPLE_ID or NOTARY_KEYCHAIN_PROFILE}"
  : "${NOTARY_PASSWORD:?set NOTARY_PASSWORD or NOTARY_KEYCHAIN_PROFILE}"
  : "${NOTARY_TEAM_ID:?set NOTARY_TEAM_ID or NOTARY_KEYCHAIN_PROFILE}"
  notarytool_creds=(
    --apple-id "$NOTARY_APPLE_ID"
    --password "$NOTARY_PASSWORD"
    --team-id "$NOTARY_TEAM_ID"
  )
fi

echo "==> Submitting $DMG to the notary service (this can take a few minutes)"
xcrun notarytool submit "$DMG" "${notarytool_creds[@]}" --wait

echo "==> Stapling the notarization ticket"
xcrun stapler staple "$DMG"

echo "==> Validating"
xcrun stapler validate "$DMG"
# Gatekeeper assessment as an end user would experience it on first open.
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "==> Done: $DMG"
