# iOS and iPad Verification

Completed 2026-07-20 for issues [#575](https://github.com/adamtheturtle/padbuddy/issues/575), [#576](https://github.com/adamtheturtle/padbuddy/issues/576), [#585](https://github.com/adamtheturtle/padbuddy/issues/585), and [#686](https://github.com/adamtheturtle/padbuddy/issues/686).

## Interaction and Phone Parity

| Capability | Evidence |
|---|---|
| Pad/question creation | Visible iOS toolbar actions plus Command-N/Shift-Command-N commands, gated by account, network, and read-only state. |
| Filters and sorting | Touch toolbar menus expose defaults, favorites, clearing, and every sort order without a macOS menu bar. |
| Row actions | Native swipe actions cover favorite, create-from-question, and delete. SwiftUI context menus provide long-press actions and compact previews. |
| Detail actions | Shared toolbars expose favorite/share/edit/end/delete. Document Actions exposes print, Markdown export, and single-file text or multifile ZIP export. |
| Keyboard | iPad command definitions cover creation, open, reload, find, command palette, sections, print/export, selection actions, and Screen actions. |
| Multi-window | Typed pad, question, and Screen-test `WindowGroup` scenes preserve the owning account ID. |
| Routing | Spotlight, widget requests, App Intents, deep links, and restoration carry account-scoped IDs into the correct phone tab/path. Invalid or removed account routes are rejected. |
| Offline | The shared navigation banner explains read-only/offline state and mutation controls consume the same environment gate. |

Automated iPad UI coverage now exercises list-to-detail navigation, favorite controls, document actions, row long-press context actions, and the touch toolbar. The generic iOS Simulator build type-checks every iOS-only branch and the embedded widget. Physical-device checks remain part of release smoke testing because Stage Manager, hardware-keyboard HUD presentation, external drag destinations, and OS scheduling cannot be faithfully asserted by a generic simulator build.

## Dynamic Type

- Text uses semantic SwiftUI styles. Fixed sizes are limited to icons/avatar geometry and code presentation, not user-facing list/detail copy.
- FastList rows may grow on iOS and macOS. At accessibility sizes the iOS row policy reduces horizontal insets and account-tint reservation, returning width to content.
- Filter bars use wrapping `FlowLayout`; dense pad rows, status badges, question materials, compact Spanish, and right-to-left layouts have render regressions.
- Settings and account switching use native Form, Menu, Label, and navigation controls, which inherit the system content-size category.

The release smoke matrix is iPad mini, 11-inch, and 13-inch sizes; portrait and landscape; narrow split and full screen; light and dark; and the largest accessibility category. A failure in that matrix is a regression, not an intentionally unsupported layout.

## iCloud and App Group

- `coderpad-iOS.entitlements` contains the team-scoped iCloud KVS identifier used by `NSUbiquitousKeyValueStore`.
- The iOS app and widget both use `group.com.adamdangoor.padbuddy`. Apple App Group identifiers intentionally use the `group.` form; the provisioning profile supplies the application-identifier prefix. The Developer ID macOS entitlement uses its separately required explicit team-prefixed identifier.
- Favorites, favorite order, and preferences use the same cloud-merge implementation on iOS and macOS. Account credentials use synchronizable Keychain storage rather than the App Group.
- The widget alone consumes App Group snapshots. App code writes those snapshots on cache/favorite changes and validates account identities when reading widget requests.

`scripts/check-ios-entitlements.swift` runs in CI so the host/widget group cannot drift and the KVS entitlement cannot silently disappear. End-to-end propagation between devices still depends on the user's iCloud account and Apple's KVS service; release smoke testing verifies one add and one removal round-trip across two signed devices.

## Main Window Account Scope

Issue [#923](https://github.com/adamtheturtle/padbuddy/issues/923) described two main windows sharing the global account selection. The product now registers the main scene as a single SwiftUI `Window`, so requesting another main window focuses the existing one. Separate pad, question, and Screen-test windows are typed scenes whose IDs contain their explicit owning account and do not retarget when the main account changes. Per-window navigation, merged routing, selection restoration, and settings presentation remain scene-scoped.
