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
| Pads | Complete: list, detail, commands, print/export/save code | Complete: shared detail actions and overflow document menu | Partial: compact shell exists, parity needs audit | Follow up in #686 |
| Questions | Complete: list, detail, favorite, create pad, commands | Complete: shared detail actions | Partial: compact shell exists, parity needs audit | Follow up in #686 |
| Organization | Complete | Complete | Complete | No immediate gap found |
| Quota | Complete | Complete | Complete when navigable | No immediate gap found |
| Screen | Partial: campaigns/tests/webhook, mostly read-only | Partial: same core flow, no menu bar | Partial: tab exists when available | Follow up in #687 |
| Settings/accounts | Complete: Settings scene and tabs | Complete: in-app full-screen settings | Partial: reachable from account menu, compact flow needs pass | Follow up in #686 |
| Widgets and controls | Complete: Recent Pads widget and New Pad control | Complete: intent drain path | Complete by system surfaces, routing needs verification | Track in #685/#686 |
| Shortcuts/App Intents | Complete for core open/search/new-pad flows | Complete | Complete, routing needs compact verification | Track in #686 |
| Spotlight/Handoff | Complete | Complete | Likely complete through iOS scene, needs device verification | Track in #685 |
| Offline/read-only | Complete | Complete | Complete banner/read-only environment | No immediate gap found |

## Pads

| Capability | macOS | iPad | iPhone | Notes |
|---|---|---|---|---|
| Browse pads | Complete | Complete | Complete | `SectionContent` and `PhoneContentView` route pads on every platform. |
| Search pads | Complete | Complete | Complete | iPhone uses `.searchable` in the Pads tab. |
| Filter/sort pads | Complete | Complete | Partial | Larger surfaces expose richer filter bars; compact parity should be verified in #686. |
| Create pad | Complete | Complete | Partial | App commands and shared navigation exist; compact new-pad question chooser is being worked on separately. |
| View/edit pad detail | Complete | Complete | Complete | Detail view is shared. |
| Share/open/watch playback | Complete | Complete | Complete | Shared toolbar actions exist where URLs are present. |
| Copy pad fields/Markdown | Complete | Partial | Partial | macOS/iPad command files expose focused copy actions; iPhone discoverability needs compact audit. |
| Print/export Markdown/save code | Complete | Complete | Partial | iPad has an overflow document menu; iPhone needs explicit compact verification. |
| Bulk delete | Complete | Complete | Partial | Bulk deletion infrastructure exists; compact selection affordance needs audit. |
| Open in new window | Complete | Complete on iPad | N/A | Separate scenes are registered for macOS and iPad. |

## Questions

| Capability | macOS | iPad | iPhone | Notes |
|---|---|---|---|---|
| Browse questions | Complete | Complete | Complete | Shared section content and phone tab exist. |
| Search questions | Complete | Complete | Complete | iPhone uses `.searchable` in the Questions tab. |
| Filter/sort questions | Complete | Complete | Partial | Compact access to all filters should be verified in #686. |
| Create question | Complete | Complete | Partial | Command and toolbar flows exist; compact create flow needs parity audit. |
| Edit title/metadata/content | Complete | Complete | Complete | Detail editor is shared. |
| Favorite question | Complete | Complete | Complete | Shared detail toolbar star and stores. |
| Create pad from question | Complete | Complete | Complete | Shared detail action and App Intent support. |
| Share/copy question | Complete | Complete | Partial | Share is shared; compact copy command equivalents need audit. |
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

The highest-priority follow-ups are already tracked:

- [#686](https://github.com/adamtheturtle/coderpad-macos/issues/686): make iPhone power workflows first-class.
- [#687](https://github.com/adamtheturtle/coderpad-macos/issues/687): round out Screen workflows.
- [#685](https://github.com/adamtheturtle/coderpad-macos/issues/685): improve background freshness and stale-data signaling.
- [#688](https://github.com/adamtheturtle/coderpad-macos/issues/688): improve diagnostics and recovery.
- [#689](https://github.com/adamtheturtle/coderpad-macos/issues/689): complete localization readiness.
- [#690](https://github.com/adamtheturtle/coderpad-macos/issues/690): complete VoiceOver and Dynamic Type audit.
