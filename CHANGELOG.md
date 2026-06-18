# Changelog

All notable changes to the CoderPad macOS app are recorded here. Versions follow
the `v<MARKETING_VERSION>` tags that drive the release pipeline; the build number is
the repository commit count, so it rises monotonically with every release.

## v0.1.5

Fixes "CoderPad can't be opened" on launch. Two signing-side issues: the packaging
script now expands Xcode entitlement variables before re-signing, and the redundant
keychain-access-groups entitlement (a provisioning-profile-required entitlement that
a Developer-ID build can't satisfy) is removed — it only restated the app's default
keychain group, so there's no functional change.

## v0.1.4

Fixes the v0.1.x builds failing to launch ("CoderPad can't be opened" / Launchd
job spawn failed): the packaging script now expands Xcode entitlement build
variables before re-signing, so keychain-access-groups and the Sparkle mach-lookup
exceptions are well-formed and AMFI allows the app to spawn.

## v0.1.3

Maintenance release — the second half of the Sparkle update-path test (#428): a
v0.1.2 install should detect, download, and install this build from the public
update feed.

## v0.1.1

Maintenance release. No functional changes over v0.1.0 — its purpose is to exercise
the in-app **Sparkle** update path end to end (a v0.1.0 install detecting,
downloading, and installing v0.1.1) now that signing + notarization are green, and to
introduce this changelog.

## v0.1.0

First distributable release, shared directly (outside the Mac App Store).

- Developer ID signed, notarized, and stapled `.dmg` — opens Gatekeeper-clean on
  other Macs.
- In-app updates via Sparkle, with a signed `appcast.xml` published alongside each
  GitHub Release (the app checks `…/releases/latest/download/appcast.xml`).
