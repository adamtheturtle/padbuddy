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
#   SIGNING_IDENTITY   Codesign certificate hash or identity name, e.g.
#                      "Developer ID Application: Your Name (TEAMID)". The
#                      matching certificate + private key must be in a keychain
#                      that is unlocked and on the search list.
#
# Notarization credentials — supply ONE of, in this precedence order:
# (1) a stored profile:
#   NOTARY_KEYCHAIN_PROFILE   A `notarytool store-credentials` profile name.
# (2) an App Store Connect API key (used for CI — scope-fixed, rotatable, and not
#     bound to a person's Apple ID):
#   ASC_KEY            The .p8 private key, base64-encoded (so it fits one secret).
#   ASC_KEY_ID         The key's ID (the 10-char string in the .p8 filename).
#   ASC_ISSUER_ID      The issuer UUID from App Store Connect → Users and Access → Keys.
#
# Optional environment:
#   SIGNING_IDENTITY_NAME Certificate name used to derive the Team ID when
#                        SIGNING_IDENTITY is a hash.
#   ENTITLEMENTS         Entitlements plist embedded when signing the app
#                        (default: PadBuddy/PadBuddy.entitlements, repo-relative).
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

APP_NAME="$(basename "$APP" .app)"
DMG="${2:-${APP%.app}.dmg}"
[[ "$DMG" == *.dmg ]] || die "output path must end in .dmg: $DMG"
[ ! -d "$DMG" ] || die "output path is a directory: $DMG"
[ ! -L "$DMG" ] || die "output path must not be a symbolic link: $DMG"

: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY (the Developer ID Application identity)}"

# Resolve the entitlements plist relative to the repo root (the dir above this
# script), so the script works regardless of the caller's working directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENTITLEMENTS="${ENTITLEMENTS:-$REPO_ROOT/PadBuddy/PadBuddy.entitlements}"
[ -f "$ENTITLEMENTS" ] || die "entitlements not found: $ENTITLEMENTS"

# Embedded app extensions (.appex) carry their own entitlements (App Sandbox +
# the widget's app-group) and must be re-signed with them — a plain re-sign, or
# one with an entitlements file that omits a key, would strip it. The file must
# therefore list every entitlement the widget needs, including
# com.apple.security.app-sandbox (which Xcode otherwise synthesizes from
# ENABLE_APP_SANDBOX at build time and which Gatekeeper expects on plug-ins).
WIDGET_ENTITLEMENTS="${WIDGET_ENTITLEMENTS:-$REPO_ROOT/RecentPadsWidgetExtension.entitlements}"
[ -f "$WIDGET_ENTITLEMENTS" ] || die "widget entitlements not found: $WIDGET_ENTITLEMENTS"

VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"

# Team ID, parsed from the certificate name ("Developer ID Application: Name
# (TEAMID)"). Needed to expand $(AppIdentifierPrefix) in the entitlements below.
TEAM_ID="$(printf '%s' "${SIGNING_IDENTITY_NAME:-$SIGNING_IDENTITY}" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')"
[ -n "$TEAM_ID" ] || die "couldn't parse a Team ID from the certificate name (set SIGNING_IDENTITY_NAME when signing by hash) — expected the form 'Developer ID Application: Name (TEAMID)'"

# codesign does NOT expand Xcode build-setting variables — only Xcode's build system
# does, during a normal build. So re-signing with the raw source .entitlements files
# would bake literal "$(PRODUCT_BUNDLE_IDENTIFIER)" / "$(AppIdentifierPrefix)" strings
# into the signature; AMFI then refuses to launch the app ("Launchd job spawn failed",
# RBSRequestErrorDomain 5 / POSIX 163) because e.g. keychain-access-groups is malformed.
# Expand those variables here, per bundle (PRODUCT_BUNDLE_IDENTIFIER is the *bundle's
# own* id, so the app and the widget get their own), and sign with the expanded copy.
ENT_WORK="$(mktemp -d)"
STAGING=""
ASC_KEY_DIR=""
NOTARY_ARCHIVE=""
MOUNT_POINT=""
MOUNTED=0
cleanup() {
  local paths=()
  if (( MOUNTED )); then
    hdiutil detach "$MOUNT_POINT" -quiet || true
  fi
  # A DMG that was created but not notarized, stapled, and assessed is not a shippable
  # artifact, and leaving one at the requested path let a failed run be mistaken for a
  # successful one — by a person or by the release workflow's own asset glob (#4633).
  if (( ! DMG_COMPLETE )) && [ -n "${DMG:-}" ] && [ -e "$DMG" ]; then
    echo "==> Removing the incomplete $DMG" >&2
    paths+=("$DMG")
  fi
  [ -n "$ENT_WORK" ] && paths+=("$ENT_WORK")
  [ -n "$STAGING" ] && paths+=("$STAGING")
  [ -n "$ASC_KEY_DIR" ] && paths+=("$ASC_KEY_DIR")
  [ -n "$NOTARY_ARCHIVE" ] && paths+=("$NOTARY_ARCHIVE")
  [ -n "$MOUNT_POINT" ] && paths+=("$MOUNT_POINT")
  (( ${#paths[@]} == 0 )) || rm -rf -- "${paths[@]}"
}
DMG_COMPLETE=0
trap cleanup EXIT

expanded_entitlements() {
  local src="$1" bundle="$2" bid out
  bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")"
  [ -n "$bid" ] || die "no CFBundleIdentifier in $bundle"
  out="$ENT_WORK/$(basename "$bundle").entitlements.plist"
  sed -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$bid|g" \
    -e "s|\$(AppIdentifierPrefix)|$TEAM_ID.|g" "$src" > "$out"
  printf '%s' "$out"
}

# --- Code signing -----------------------------------------------------------
# Sign with Hardened Runtime (--options runtime) and a secure timestamp; both
# are required for notarization. Sign nested code inside-out before the app, as
# Apple recommends over a single `--deep` pass.
sign() {
  codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$@"
}

# True if the path contains at least one Mach-O file — i.e. actual code that
# must be Developer-ID signed. Resource-only bundles (e.g. an SPM
# `<pkg>_<target>.bundle` carrying fonts/plists) contain none: they get sealed
# into their containing bundle's signature when that is signed, and codesign
# refuses to sign ones that lack an Info.plist ("bundle format unrecognized").
contains_macho() {
  find "$1" -type f -exec file {} + 2>/dev/null | grep 'Mach-O' >/dev/null
}

echo "==> Signing nested code in $APP"
# Frameworks, dylibs, and any embedded helper executables, deepest path first.
# Frameworks and dylibs are always code; a .bundle only needs its own signature
# when it actually contains a Mach-O (a loadable bundle).
while IFS= read -r -d '' nested; do
  case "$nested" in
  *.bundle)
    if ! contains_macho "$nested"; then
      echo "    skip (resources only): ${nested#"$APP"/}"
      continue
    fi
    ;;
  *.xpc | *.app)
    # Sparkle embeds pre-signed XPC services (Installer.xpc, and Downloader.xpc for
    # sandboxed apps) plus an Updater.app inside its framework. Signing the framework
    # does NOT re-sign these nested code bundles — they keep Sparkle's own signature,
    # which the notary rejects ("not signed with a valid Developer ID certificate" /
    # "signature does not include a secure timestamp"). Re-sign each with our
    # Developer ID + Hardened Runtime + a secure timestamp, preserving its own
    # entitlements so sandboxed Sparkle keeps working. The deepest-first sort below
    # guarantees these are signed before the framework that contains them.
    echo "    sign (preserve entitlements): ${nested#"$APP"/}"
    codesign --force --options runtime --timestamp \
      --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$nested"
    continue
    ;;
  esac
  echo "    sign: ${nested#"$APP"/}"
  sign "$nested"
done < <(
  find "$APP/Contents" \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.bundle' \
      -o -name '*.xpc' -o -name '*.app' -o -name 'Autoupdate' \) \
    -print0 | sort -rz
)

# App extensions (.appex) come after the frameworks/dylibs nested inside them
# (signed above, deepest-first) but before the outer app. Each must be
# Developer-ID signed with Hardened Runtime + a timestamp AND keep its own
# entitlements; a plain re-sign would drop the widget's App Sandbox + app-group.
# The outer `codesign "$APP"` below does NOT re-sign nested .appex bundles, and
# `codesign --verify` passes on an ad-hoc-signed appex — so a missed appex only
# surfaces when the notary service rejects it.
# Always re-sign WITH the extension's own entitlements — a plain `sign "$appex"`
# would strip App Sandbox + the app-group, the very failure this guards against.
# The entitlements file's existence is checked up front (above), so there is no
# silent strip-on-fallback path here.
#
# The widget's entitlements are applied to the widget, by bundle identifier. They used
# to be applied to every `*.appex` found, so a future or nested extension would have
# been signed with another extension's App Sandbox and app-group grants — which the
# notary service accepts and which is wrong at runtime (issue #4632). An unrecognised
# extension fails here instead, so adding one is a deliberate decision about what it may
# access.
WIDGET_BUNDLE_ID="${WIDGET_BUNDLE_ID:-com.adamdangoor.padbuddy.RecentPadsWidget}"
while IFS= read -r -d '' appex; do
  appex_bid="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$appex/Contents/Info.plist")"
  case "$appex_bid" in
    "$WIDGET_BUNDLE_ID")
      appex_entitlements="$WIDGET_ENTITLEMENTS"
      ;;
    *)
      die "unrecognised app extension $appex_bid at ${appex#"$APP"/}; add its entitlements mapping before signing"
      ;;
  esac
  echo "    sign appex: ${appex#"$APP"/} ($appex_bid)"
  sign --entitlements "$(expanded_entitlements "$appex_entitlements" "$appex")" "$appex"
done < <(find "$APP/Contents" -name '*.appex' -print0 | sort -rz)

echo "==> Signing app bundle (entitlements: ${ENTITLEMENTS#"$REPO_ROOT"/})"
sign --entitlements "$(expanded_entitlements "$ENTITLEMENTS" "$APP")" "$APP"

rm -rf "$ENT_WORK"
ENT_WORK=""

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- Notarization credentials ----------------------------------------------
notarytool_creds=()
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  notarytool_creds=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else
  : "${ASC_KEY:?set ASC_KEY (+ ASC_KEY_ID/ASC_ISSUER_ID) or NOTARY_KEYCHAIN_PROFILE}"
  : "${ASC_KEY_ID:?set ASC_KEY_ID alongside ASC_KEY}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID alongside ASC_KEY}"
  # The .p8 is supplied base64-encoded so it fits in a single CI secret. Decode
  # it to a private temp file (umask 077) that notarytool can read, in its own
  # dir so the shared EXIT trap can shred it.
  ASC_KEY_DIR="$(mktemp -d)"
  ASC_KEY_PATH="$ASC_KEY_DIR/asc-api-key.p8"
  ( umask 077; printf '%s' "$ASC_KEY" | base64 --decode > "$ASC_KEY_PATH" )
  notarytool_creds=(
    --key "$ASC_KEY_PATH"
    --key-id "$ASC_KEY_ID"
    --issuer "$ASC_ISSUER_ID"
  )
fi

notarize() {
  local artifact="$1" description="$2" submit_output submit_rc submission_id
  echo "==> Submitting $description to the notary service (this can take a few minutes)"
# `notarytool submit --wait` exits 0 even when the result is `Invalid`, so capture
# the output, pull out the submission id, and only proceed on `Accepted`. On any
# other status fetch the detailed notary log (the only place that lists *why* a
# binary was rejected — signing/entitlements/hardened-runtime issues) and fail.
  set +e
  submit_output="$(xcrun notarytool submit "$artifact" "${notarytool_creds[@]}" --wait 2>&1)"
  submit_rc=$?
  set -e
  printf '%s\n' "$submit_output"
  submission_id="$(printf '%s\n' "$submit_output" | awk '/^[[:space:]]*id:/ { print $2; exit }')"

  if ! printf '%s\n' "$submit_output" | grep -q 'status: Accepted'; then
    if [ -n "$submission_id" ]; then
      echo "==> Notarization was not Accepted — fetching the notary log for $submission_id"
      xcrun notarytool log "$submission_id" "${notarytool_creds[@]}" || true
    fi
    die "notarization failed for $description (notarytool exit $submit_rc; status not Accepted)"
  fi
}

# Notarize and staple the app itself before copying it into the disk image.
# A stapled inner bundle remains verifiable after the user copies it out of the
# DMG, including when Gatekeeper cannot reach Apple's ticket service.
NOTARY_ARCHIVE="$(mktemp -d)"
APP_ZIP="$NOTARY_ARCHIVE/$APP_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$APP_ZIP"
notarize "$APP_ZIP" "app bundle"

echo "==> Stapling and validating app notarization ticket"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

# --- Package as .dmg --------------------------------------------------------
echo "==> Building $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag-to-install target
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG"

echo "==> Signing $DMG"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"

# Notarize the final container separately so both distribution layers carry
# their own locally stapled ticket.
notarize "$DMG" "disk image"

echo "==> Stapling the disk image notarization ticket"
xcrun stapler staple "$DMG"

echo "==> Validating"
xcrun stapler validate "$DMG"
# Gatekeeper assessment as an end user would experience it on first open.
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "==> Assessing the packaged app"
MOUNT_POINT="$(mktemp -d)"
hdiutil attach "$DMG" -readonly -nobrowse -mountpoint "$MOUNT_POINT" -quiet
MOUNTED=1
PACKAGED_APP="$MOUNT_POINT/$APP_NAME.app"
[ -d "$PACKAGED_APP" ] || die "packaged app not found at $PACKAGED_APP"
codesign --verify --deep --strict --verbose=2 "$PACKAGED_APP"
spctl --assess --type execute --verbose=2 "$PACKAGED_APP"
hdiutil detach "$MOUNT_POINT" -quiet
MOUNTED=0
rmdir "$MOUNT_POINT"
MOUNT_POINT=""

DMG_COMPLETE=1
echo "==> Done: $DMG"
