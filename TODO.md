# TODO — toward a truly great CoderPad client

A living roadmap. Items are grouped by theme and roughly ordered by impact. Anything that requires Xcode project-file edits I can't make from the agent (target settings, capabilities, supported platforms) is marked **[manual]**.

## Blocking the basic happy path

- [ ] **[manual]** Tick **App Sandbox → Outgoing Connections (Client)** for the `coderpad` target. Without this, every API call fails with `NSURLErrorDomain -1003`.
- [ ] **[manual]** Rotate the API key that was pasted into chat earlier (it's in git history of the conversation, not the repo).

## Onboarding

- [ ] In Settings → Accounts, add a small banner with the "Get an API key" link (already in the editor sheet) plus the latest scopes the key needs.
- [ ] Validate keys not just for *can-reach-org* but also surface which scopes are missing if a 403 comes back from any endpoint.

## Data freshness & navigation

- [ ] Auto-refresh pads list every N minutes when the window is foregrounded; respect `state == "started"` and bias toward those.
- [ ] Show a "last fetched X ago" indicator near the reload button.
- [ ] Persist last-selected section per account (currently resets to Pads each launch).
- [ ] Pinned pads — let users star a pad and keep it at the top, scoped per account.
- [ ] Diff highlights when reloading: subtle badge on pads that changed since last refresh.

## Search & filtering

- [x] Filters in pads (state, language, owner, team, type) and questions (language, owner, take-home, status).
- [x] Searchable owner filter (popover with text field).
- [ ] Date-range filters (created / updated).
- [ ] Save searches as named views ("Live pads, my team, today").
- [ ] Spotlight integration via Core Spotlight so pads + questions are findable system-wide.

## Write paths (currently only Create Pad is implemented)

- [ ] PUT `/api/pads/` — update an existing pad's title / language / private / execution / notes.
- [ ] POST `/api/questions/` — create question with description, candidate instructions, solution, language, take-home toggle.
- [ ] PUT `/api/questions/:id` — edit.
- [ ] DELETE `/api/questions/:id` — with a confirmation sheet and an undo grace period (re-create from cached fields).
- [ ] Bulk actions on pads (end started pads, mark private).

## Pad detail polish

- [ ] In-pad code preview: show the `contents` and/or active environment code with syntax highlighting (CodeEditor / TextKit2).
- [ ] Events timeline grouping (collapse consecutive `typed` events).
- [ ] Highlight the active participant in the events timeline.
- [ ] "Open in Pad Browser" button on individual events when the API exposes a deep-link.

## Menu bar item

- [x] Recent "My Pads" with switch-account, reload, open main, quit.
- [ ] Show a subtle dot when a started pad has new activity since last open.
- [ ] Section sub-menus: Recent Questions, Recent Activity.
- [ ] Configurable: show top N pads, filter by owner = me, show only started pads.

## App menu / commands

- [x] Custom About panel.
- [x] Help menu: API docs, Get API Key, Source.
- [x] File → New Pad… (⌘N), Reload (⌘R).
- [x] Go → Pads/Questions/Org/Quota (⌘1–⌘4).
- [ ] File → Open Pad by URL… (⌘O) — paste a pad URL and the in-window browser opens it directly.
- [ ] Edit → Copy current pad ID / URL.

## Accessibility & ergonomics

- [ ] VoiceOver labels on filter chips, stat tiles, and the event timeline.
- [ ] Dynamic Type for body text (most labels already use semantic fonts; verify in pad detail).
- [ ] High-contrast mode pass for the chip backgrounds (current alphas are subtle).
- [ ] Keyboard navigation through pad list with `↑/↓`, `↩` to open in-window browser.

## Multi-platform

- [ ] **[manual]** Add **iPad** to the target's supported destinations (Signing & Capabilities tab or `SUPPORTED_PLATFORMS` build setting). I can't edit `project.pbxproj` from the agent — once you add it, I'll:
    - guard `NSPasteboard`, `NSWorkspace`, `NSApp`, `NSAttributedString`, `WKWebView`-via-`NSViewRepresentable`, `MenuBarExtra`, the `Settings` scene, and `MenuBarView` with `#if os(macOS)`
    - add `UIPasteboard`, `UIApplication.shared.open`, and `WKWebView`-via-`UIViewRepresentable` equivalents
    - swap the three-column `NavigationSplitView` for a two-column layout on compact width.
- [ ] **iPhone**: same code path as iPad, but the third column collapses to a push.
- [ ] **visionOS**: NavigationSplitView mostly transfers. No `MenuBarExtra` / no `Settings` scene; settings becomes a regular window. Hover and tap interactions need verification.
- [ ] **tvOS**: this is the biggest gap. The focus engine, no popovers, no text fields-by-keyboard, no `Settings` scene, and the entire filter chip system would need a redesigned remote-friendly UI. Tracked separately — propose: read-only browse of recent pads/questions, no create/edit, no settings UI (provision the key via deep link from the iPhone companion).

## Distribution

- [ ] Sparkle (or built-in `SUUpdater`) for in-app updates from GitHub Releases.
- [ ] Notarized release built from CI on tag push.
- [ ] Generate release notes from `git log` automatically.

## Tests & CI

- [x] Decoder tests (Pad, Question, Quota — null-tolerance and date formats).
- [x] Mock server + integration tests (listPads, getPad, padEvents, createPad, organization, quota).
- [x] GitHub Actions workflow.
- [ ] **[manual?]** macOS deployment target is 26.4; the CI runner needs a matching SDK. If GitHub Actions hasn't shipped that yet, lower the target to macOS 14.0 — none of the code I've written requires 26.4.
- [ ] UI tests for: add account, switch to demo, browse pads, open pad in in-window browser.
- [ ] Snapshot tests for the design-system primitives.

## Quality / refactoring

- [ ] Centralize URL session construction (currently `.shared` for real, `MockServer.session()` for demo).
- [ ] Replace ad-hoc `errorMessage: String?` storage with `Error?` everywhere (PadDetailView's load error is still a string).
- [ ] Extract `OrgDirectory` cache to also be used by Question owner display (currently only Pad views use it).
- [ ] Add Sendable annotations across `MockFixtures` (currently uses `nonisolated(unsafe)` for `createdPads`).

## Security

- [ ] Periodic key health check: silently call `/api/organization` once a day; if 401, surface a banner before the user discovers it.
- [ ] Option to require Touch ID before revealing a saved key in Settings.
- [ ] Audit the Keychain item's access group; currently uses the default Generic Password class.
