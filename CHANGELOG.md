# Changelog

All notable changes to the CoderPad macOS app are recorded here. Versions follow
the `v<MARKETING_VERSION>` tags that drive the release pipeline; the build number is
the repository commit count, so it rises monotonically with every release.

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
