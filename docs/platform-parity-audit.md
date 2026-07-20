# Platform Parity Audit

Tracking issue: [#684](https://github.com/adamtheturtle/coderpad-macos/issues/684)

This audit records the current cross-platform shape of PadBuddy from the Swift sources. It is a product parity map, not a replacement for device verification. The simulator/device interaction tools were not available when this audit was written, so visual and assistive-technology findings belong in the dedicated accessibility audit.

Legend:

- Complete: implemented with a platform-appropriate affordance.
- Partial: present, but weaker or less discoverable than another platform.
- N/A: intentionally platform-specific.
- Follow-up: needs a focused implementation issue or product decision.

## Summary

| Area | macOS | iPad | iPhone | Status |
|---|---|---|---|---|
| Main navigation | Complete: split view, sidebar, commands | Complete: split view and multi-window scenes | Complete: tab shell with stacks | Monitor iPhone parity as features expand |
| Pads | Complete: list, detail, commands, print/export/save code | Complete: shared detail actions and overflow document menu | Complete: compact creation, filters, sorting, row/detail actions | Verified in #686 |
| Questions | Complete: list, detail, favorite, create pad, commands | Complete: shared detail actions | Complete: compact creation, filters, sorting, row/detail actions | Verified in #686 |
| Organization | Complete | Complete | Complete | No immediate gap found |
| Quota | Complete | Complete | Complete when navigable | No immediate gap found |
| Screen | Partial: campaigns/tests/webhook, mostly read-only | Partial: same core flow, no menu bar | Partial: tab exists when available | Follow up in #687 |
| Settings/accounts | Complete: Settings scene and tabs | Complete: in-app full-screen settings | Complete: account menu exposes settings, management, add, and switching | Verified in #686 |
| Widgets and controls | Complete: Recent Pads widget and New Pad control | Complete: ordered, validated intent drain | Complete: account-scoped requests route into phone paths | Verified in #686 |
| Shortcuts/App Intents | Complete for core open/search/new-pad flows | Complete | Complete: compact routing uses shared request mailboxes | Verified in #686 |
| Spotlight/Handoff | Complete | Complete | Complete: iOS scene validates and routes typed references | Verified in #686 |
| Offline/read-only | Complete | Complete | Complete banner/read-only environment | No immediate gap found |

## Pads

| Capability | macOS | iPad | iPhone | Notes |
|---|---|---|---|---|
| Browse pads | Complete | Complete | Complete | `SectionContent` and `PhoneContentView` route pads on every platform. |
| Search pads | Complete | Complete | Complete | iPhone uses `.searchable` in the Pads tab. |
| Filter/sort pads | Complete | Complete | Complete | Compact toolbar exposes suggestions, clear, and sort menus. |
| Create pad | Complete | Complete | Complete | Compact toolbar and App Intent both reach the shared creation flow. |
| View/edit pad detail | Complete | Complete | Complete | Detail view is shared. |
| Share/open/watch playback | Complete | Complete | Complete | Shared toolbar actions exist where URLs are present. |
| Copy pad fields/Markdown | Complete | Complete | Complete | Context/overflow actions expose compact equivalents. |
| Print/export Markdown/save code | Complete | Complete | Complete | Shared Document Actions adapts presentation to compact width. |
| Bulk delete | Complete | Complete | Intentional single-row phone flow | Phone uses destructive row actions; bulk selection remains a large-screen workflow. |
| Open in new window | Complete | Complete on iPad | N/A | Separate scenes are registered for macOS and iPad. |

## Questions

| Capability | macOS | iPad | iPhone | Notes |
|---|---|---|---|---|
| Browse questions | Complete | Complete | Complete | Shared section content and phone tab exist. |
| Search questions | Complete | Complete | Complete | iPhone uses `.searchable` in the Questions tab. |
| Filter/sort questions | Complete | Complete | Complete | Compact toolbar exposes suggestions, favorites, clear, and sort menus. |
| Create question | Complete | Complete | Complete | Compact toolbar reaches the shared creation sheet. |
| Edit title/metadata/content | Complete | Complete | Complete | Detail editor is shared. |
| Favorite question | Complete | Complete | Complete | Shared detail toolbar star and stores. |
| Create pad from question | Complete | Complete | Complete | Shared detail action and App Intent support. |
| Share/copy question | Complete | Complete | Complete | Shared detail and context actions provide compact equivalents. |
| Delete with undo grace period | Complete | Complete | Complete | Shared detail implementation includes delayed deletion. |
| Open in new window | Complete | Complete on iPad | N/A | Separate scenes are registered for macOS and iPad. |

## Screen

| Capability | macOS | iPad | iPhone | Notes |
|---|---|---|---|---|
| Show campaigns | Complete | Complete | Complete when Screen credentials exist | Gated by Screen client availability. |
| Search campaigns | Complete | Complete | Complete | Search binding is available; selected campaign changes search target to tests. |
| Show archived campaigns | Complete | Complete | Complete | Toolbar toggle exists, compact discoverability should be verified. |
| Show test sessions | Complete | Complete | Complete | Detail column on large layouts; compact route needs hands-on verification. |
| Open test report in new window | Complete | Complete on iPad | N/A | Separate Screen test scene is registered for macOS/iPad. |
| Webhook configuration | Complete for single account | Complete for single account | Partial | Needs compact verification and merged-account product decision. |
| Mutating Screen workflows | Follow-up | Follow-up | Follow-up | The current native Screen UI is mostly read-only; see #687. |

## System Surfaces

| Surface | macOS | iPad | iPhone | Notes |
|---|---|---|---|---|
| Recent Pads widget | Complete | Complete | Complete | Uses shared App Group snapshots. |
| New Pad control | Complete where supported | Complete | Complete | Implemented with App Intents, not custom URL schemes. |
| App Shortcuts | Complete | Complete | Complete | Open/search/new-pad intents exist. |
| Focus filter | Complete where supported | Complete where supported | Complete where supported | Account scoping intent exists. |
| Spotlight | Complete | Complete | Needs verification | Shared continuation handling exists in iOS scene. |
| Handoff/Siri suggestions | Complete | Complete | Needs verification | Pad activity path exists on app scenes. |
| Menu bar extra | Complete | N/A | N/A | Platform-specific macOS value. |
| MCP server/settings | Complete | N/A | N/A | Platform-specific macOS value. |

## Follow-Ups

The remaining highest-priority follow-ups are:

- [#687](https://github.com/adamtheturtle/coderpad-macos/issues/687): round out Screen workflows.
- [#707](https://github.com/adamtheturtle/coderpad-macos/issues/707): adopt newly discovered API metadata after its upstream model work lands.
