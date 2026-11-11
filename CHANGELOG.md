# Changelog

All notable changes to the CoderPad macOS app are recorded here.
Versions follow the `v<MARKETING_VERSION>` tags that drive the release pipeline; the build number rises monotonically with every release.

## v0.3.0

- Create project environments directly from New Pad, including Python projects, React, and Django.
- Let connected assistants discover available environments and starter code before creating project pads.
- Support custom project starter files through the embedded MCP server.

## v0.2.1

- Improve account loading, snapshot isolation, cancellation, caching, and background refresh reliability.
- Render multi-file project starter code and strengthen question, pad, and Screen editing workflows.
- Fix deep-link, widget, browser, navigation, persistence, and validation edge cases.
- Restore Vision Pro pad and question selection, rail accessibility, and account settings interactions.
- Add deterministic first-account loading coverage with a 100-pad performance budget.
- Repair isolated core UI verification and expand larger-text Vision simulator coverage.
- Harden release versioning, signing validation, packaging, update-feed integrity, and source provenance.

## v0.2.0

- Manage language and project-template variants from a question’s Variants pane, including starter files, hidden files, and reference solutions.
- Create Screen campaigns from selected or randomly ordered bank questions.
- Browse bank questions, inspect evaluations and insights, and create or edit supported question types with native forms.
- Upload gzip project archives for new project questions.
- Inspect typed Screen results and AI conversations, and export result archives.
- View Interview analytics, transcripts, and reviews.
- Configure Interview participants, candidate controls, question names, sharing, and database associations.
- Duplicate pads with explicit webhook delivery control.
- Update the Interview and Screen SDK and embedded MCP tools.
- Correct printing pagination, background cancellation and timeout scheduling, and persistence test isolation.

## v0.1.17

- Restored private package access in release builds with the package deploy key.

## v0.1.16

- Added authenticated package access to the release workflow.

## v0.1.15

- Fixed private Swift package resolution during direct releases.

## v0.1.14

- Added Spanish localization coverage and an accessibility release gate.
- Added Apple Watch support and hardened Foundation Models architecture guards.
- Stabilized archive, compiler, highlighted-code layout, and version validation paths.

## v0.1.13

- Simplified the product by retiring Saved Search, Smart Filter, Pad Evaluation, and interview templates.
- Improved macOS list/edit affordances, keyboard shortcuts, Screen workflows, browser routing, and iPad widget actions.

## v0.1.12

- Added App Store submission materials, Xcode Cloud archive support, and screenshot capture.
- Adopted remote PaginatedRESTClient and WhatsNewKit packages.
- Updated localization catalogs and reduced several Swift type-checking hot spots.

## v0.1.11

- Renamed the product to PadBuddy and added the unofficial-client disclaimer.
- Expanded widget creation support and fixed App Store encryption metadata.
- Improved appearance controls, pad detail performance, previews, and design-system reuse.

## v0.1.10

- Added the Sparkle-free App Store target and source membership.
- Fixed widget backgrounds and removed a duplicate Info.plist.
- Moved linting to Linux and expensive release builds to nightly/manual CI.

## v0.1.9

- Fixed the widget New Pad action and small-widget rendering.

## v0.1.8

- Improved sidebar presentation and keyboard navigation.
- Refined Screen selection, New Pad routing, and launch seeding.
- Adopted the Liquid Glass app icon and tightened notarization and dead-code checks.

## v0.1.7

- Added pad Favorite context actions and broader section keyboard navigation.
- Fixed UI-test compatibility and stale DerivedData restoration.

## v0.1.6

- Stabilized CI build/test settings and Swift type-checking.
- Added Screen demo-data tests and adopted shared design-system packages.

## v0.1.5

- Removed the explicit Keychain access group from the Developer ID build.

## v0.1.4

- Fixed entitlement expansion so Developer ID builds launch correctly.

## v0.1.3

- Added another end-to-end Sparkle update-path release.

## v0.1.2

- Moved Sparkle update artifacts to the public releases repository while keeping source private.

## v0.1.1

Maintenance release.
No functional changes over v0.1.0 — its purpose is to exercise the in-app **Sparkle** update path end to end (a v0.1.0 install detecting, downloading, and installing v0.1.1) now that signing + notarization are green, and to introduce this changelog.

## v0.1.0

First distributable release, shared directly (outside the Mac App Store).

- Developer ID signed, notarized, and stapled `.dmg` — opens Gatekeeper-clean on other Macs.
- In-app updates via Sparkle, with a signed `appcast.xml` published alongside each GitHub Release (the app checks `…/releases/latest/download/appcast.xml`).
