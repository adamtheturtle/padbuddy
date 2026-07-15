# Cross-Cutting Quality Audit

Tracking issues:

- [#688](https://github.com/adamtheturtle/coderpad-macos/issues/688): diagnostics and recovery paths
- [#689](https://github.com/adamtheturtle/coderpad-macos/issues/689): localization and internationalization
- [#690](https://github.com/adamtheturtle/coderpad-macos/issues/690): VoiceOver and Dynamic Type

This checklist is scoped to the app surfaces identified in the platform parity audit. It gives each broad issue a concrete definition of done and separates source inspection from device verification.

## Accessibility

### Source-Level Checks

| Surface | VoiceOver | Dynamic Type | Notes |
|---|---|---|---|
| No-account and onboarding | Needs audit | Needs audit | Verify primary action labels and explanatory text order. |
| Account editor | Partial | Needs audit | API key reveal buttons have labels; form grouping and error announcement need verification. |
| Settings tabs | Needs audit | Needs audit | Confirm tab names, detail placeholder, and account list selection state. |
| Sidebar and account footer | Partial | Needs audit | Several labels exist; merged-account and unauthorized states need VoiceOver verification. |
| Pads list | Needs audit | Needs audit | Rows should expose title, state, owner, date, language, and selection/favorite state. |
| Questions list | Needs audit | Needs audit | Custom macOS table accessibility should be verified against SwiftUI list behavior. |
| Filter chips | Partial | Needs audit | Existing labels/values are promising; popover picker order and clear actions need verification. |
| Pad detail | Partial | Needs audit | Shared toolbar labels exist; inline title/property editors need focus and announcement checks. |
| Question detail | Partial | Needs audit | Favorite/new-pad/share/delete labels exist; segmented pane and inline editors need checks. |
| Screen campaigns/tests | Partial | Needs audit | Campaign rows expose text visually; test session report grouping needs verification. |
| Command palette | Needs audit | Needs audit | Verify search field, result rows, keyboard selection, and dismissal announcements. |
| Widgets | Needs audit | Needs audit | Widget family layouts need large text and VoiceOver labels. |

### Device Verification Matrix

Run these on macOS, iPad, and iPhone where available:

- VoiceOver reads every interactive control with a useful label and role.
- Selection state is announced for selected account, selected row, active filter, favorite state, and selected Screen campaign.
- Destructive actions announce destructive intent and require confirmation where appropriate.
- Dynamic Type at accessibility sizes does not overlap, truncate critical labels, or hide primary actions.
- Reduce Motion avoids nonessential animation where the app already branches on `accessibilityReduceMotion`.
- High contrast and increased contrast preserve row selection, filter chips, status badges, and toolbar affordances.

## Localization

### Source-Level Checks

| Area | Status | Notes |
|---|---|---|
| SwiftUI app strings | Partial | Many strings use localized APIs, but literal labels should be catalog-audited. |
| Menu commands | Needs audit | macOS command titles and iPad command titles should appear in catalogs. |
| App Intents and Shortcuts | Partial | `LocalizedStringResource` is used; phrase coverage and translations need catalog checks. |
| Widget strings | Needs audit | Configuration parameters, row labels, empty states, and button labels need coverage. |
| Error messages | Partial | `CoderPadKit+Presentation` uses localized strings; API-specific messages need translator context. |
| Pluralization | Needs audit | Count strings for pads/questions/campaigns should use catalog plural variants where appropriate. |
| Interpolation comments | Needs audit | Translator comments are needed for labels that include account names, dates, or states. |
| Right-to-left layout | Needs device verification | Especially sidebar, filter chips, row metadata, widgets, and command palette. |
| App Store metadata | Needs audit | Existing app-store docs should match current feature names and terminology. |

### Acceptance Checklist

- Every user-facing literal is either intentionally not localized or appears in the appropriate string catalog.
- Count strings use plural-aware localization instead of English-only conditional text where practical.
- Interpolated strings include comments when variable meaning is not obvious.
- Long translations fit compact iPhone navigation bars, toolbar menus, widgets, and settings forms.
- Right-to-left smoke testing is documented with screenshots or follow-up issues.

## Diagnostics and Recovery

### Failure Surfaces

| Surface | Needed Recovery Behavior |
|---|---|
| Account validation | Explain invalid key, missing scopes, unreachable server, and rate limits without exposing secrets. |
| Merged accounts | Identify which account failed while preserving healthy account data. |
| Disk caches | Show stale data timestamps and retry affordances when refresh fails. |
| iCloud Keychain sync | Log privacy-safe status and recover from unavailable or conflicting data. |
| Favorites/preferences sync | Preserve local data and explain sync unavailability without blocking app use. |
| Widget snapshots | Make stale widget data understandable and refresh when app caches update. |
| App Intents/deep links | Preserve route requests across cold launch and report unrecoverable invalid input clearly. |
| Spotlight indexing | Avoid stale deleted items and log indexing failures without pad/question contents. |
| Screen API | Include account and region context in errors, never API keys or candidate payloads. |
| MCP server/tools | Distinguish disabled server, read-only permissions, invalid arguments, API failures, and write restrictions. |

### Privacy Rules

Diagnostics must not include:

- API keys or Screen keys
- pad code contents
- candidate names, emails, resumes, or report payloads
- full question prompts or solutions
- raw keychain payloads

Diagnostics may include:

- account display name or stable local account id
- section name
- HTTP status category or safe CoderPad error description
- cache age and refresh result
- widget/App Intent route type
- MCP tool name and success/failure state

## Recommended Implementation Order

1. Finish device verification for #690 and file narrow UI bugs.
2. Catalog-audit literals and plurals for #689 before adding new translated strings.
3. Add stale-data timestamps and merged-account partial-failure recovery for #685/#688.
4. Add privacy-safe diagnostics around widget/App Intent routing after iPhone compact routing is verified in #686.
