# Cross-Cutting Quality Audit

Tracking issues:

- [#688](https://github.com/adamtheturtle/padbuddy/issues/688): diagnostics and recovery paths
- [#689](https://github.com/adamtheturtle/padbuddy/issues/689): localization and internationalization
- [#690](https://github.com/adamtheturtle/padbuddy/issues/690): VoiceOver and Dynamic Type

This checklist is scoped to the app surfaces identified in the platform parity audit. It gives each broad issue a concrete definition of done and separates source inspection from device verification.

## Accessibility — completed 2026-08-03

The release-gate refresh reran the focused accessibility render and layout suites on
macOS 26 with Xcode 27 beta. Accessibility-size pad/question rows, pad detail,
compact Spanish and right-to-left question detail, detail-chip semantics, and
FastList accessibility-width policies all passed. Source review also confirmed the
new multi-file/ZIP controls expose text labels, progress, validation, cancellation,
and error states. Platform VoiceOver and spatial-window checks remain explicitly
tracked by the repository's interactive/visual-verification issues; they are not
silently treated as automated coverage.

### Accessibility Source-Level Checks

| Surface | VoiceOver | Dynamic Type | Notes |
|---|---|---|---|
| No-account, account editor, settings | Complete | Native | Native buttons/forms expose labels and traits; key visibility and tab controls have explicit labels. |
| Sidebar and account footer | Complete | Native | Selection stays native; decorative symbols are hidden and status text remains readable. |
| Pad and question lists | Complete | Guarded | Custom rows expose meaningful text/actions; accessibility-size render tests cover dense pad rows and question materials. |
| Filters and search | Complete | Wrapping | Chips provide labels, values, hints, and clear actions; `FlowLayout` wraps at larger sizes. |
| Pad and question detail | Complete | Guarded | Editors and icon-only actions are labelled; compact, RTL, and accessibility-size render tests cover custom detail content. |
| Screen campaigns/tests | Complete | Native | Lists retain native selection traits and report actions have text labels. |
| Command palette/title editing | Complete | Guarded | Search/results use native controls; narrow-title render coverage prevents zero-width editing. |
| Widgets | Complete | System | Widget text and links use WidgetKit semantics and scalable SwiftUI text. |

### Manual Regression Matrix

Run these on macOS, iPad, and iPhone where available:

- VoiceOver reads every interactive control with a useful label and role.
- Selection state is announced for selected account, selected row, active filter, favorite state, and selected Screen campaign.
- Destructive actions announce destructive intent and require confirmation where appropriate.
- Dynamic Type at accessibility sizes does not overlap, truncate critical labels, or hide primary actions.
- Reduce Motion avoids nonessential animation where the app already branches on `accessibilityReduceMotion`.
- High contrast and increased contrast preserve row selection, filter chips, status badges, and toolbar affordances.

## Localization

### Localization Source-Level Checks

| Area | Status | Notes |
|---|---|---|
| SwiftUI app strings | Automated gate passing | `swift scripts/check-localization.swift` verifies required Spanish translations for extracted app strings. |
| Menu commands | Automated gate passing | Extracted command titles are covered by `coderpad/Localizable.xcstrings`; manual review is still useful for terminology. |
| App Intents and Shortcuts | Automated gate passing | `AppShortcuts.xcstrings` is included in the catalog completeness gate. |
| Widget strings | Automated gate passing | `RecentPadsWidget/Localizable.xcstrings` and `InfoPlist.xcstrings` are included in the catalog completeness gate. |
| Error messages | Partial | `CoderPadKit+Presentation` uses localized strings; API-specific messages need translator context. |
| Pluralization | Needs audit | Count strings for pads/questions/campaigns should use catalog plural variants where appropriate. |
| Interpolation comments | Needs audit | Translator comments are needed for labels that include account names, dates, or states. |
| Right-to-left layout | Needs device verification | Especially sidebar, filter chips, row metadata, widgets, and command palette. |
| App Store metadata | Needs audit | Existing app-store docs should match current feature names and terminology. |

### 2026-07-15 Automated Localization Check

- `swift scripts/check-localization.swift` passed after filling missing Spanish entries in all five string catalogs.
- Required catalog coverage currently includes `coderpad/Localizable.xcstrings`, `coderpad/AppShortcuts.xcstrings`, both app/widget `InfoPlist.xcstrings` files, and `RecentPadsWidget/Localizable.xcstrings`.
- This does not replace manual RTL and long-label layout checks on compact iPhone, iPad split layouts, widgets, menus, and settings forms.

### Acceptance Checklist

- Every extracted user-facing literal has a required Spanish catalog entry.
- Count strings use plural-aware localization instead of English-only conditional text where practical.
- Interpolated strings include comments when variable meaning is not obvious.
- Long translations fit compact iPhone navigation bars, toolbar menus, widgets, and settings forms.
- Right-to-left smoke testing is documented with screenshots or follow-up issues.

## Diagnostics and Recovery — completed 2026-07-20

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

The audited paths now provide those behaviors: merged loads retain healthy cached data and name failed accounts; standalone and Screen surfaces use retryable stale-data banners; account authorization routes to Settings; widget/App Intent requests validate account identifiers and survive cold launch; Spotlight serializes writes, times out stuck operations, and privately logs error descriptions; MCP records tool, permission, account/region context, and success/failure without payloads. Background failures use bounded exponential retry and stable local account identifiers.

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

## Freshness — completed 2026-07-20

- Merged pad and question lists show `Refreshing`, `Updated just now`, or elapsed freshness and preserve healthy-account results when another account fails.
- Standalone pad, question, Screen test, quota, and organization views show cached content with a retryable stale-data banner on refresh failure.
- Every persisted pad-cache mutation refreshes the widget snapshot, Dock badge inputs, favorites, and Spotlight. WidgetKit ultimately controls display scheduling, so exact delivery time is not promised.
- Background pad monitoring records privacy-safe failure categories, applies bounded exponential backoff, and drives explicit, configurable pad-update notifications. Notification bodies omit pad contents and candidate data.
- Platform limits remain explicit: foreground refresh and user retries are immediate; background execution, WidgetKit timelines, notification delivery, and Spotlight ingestion are scheduled by the operating system.

## Ongoing Regression Order

1. Run the manual accessibility matrix after adding a custom control or new widget family.
2. Catalog-audit literals and plurals before adding translated strings.
3. Add every new refresh surface to the freshness and diagnostics tables above.
