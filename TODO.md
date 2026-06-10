# TODO — toward a truly great CoderPad client

A living roadmap. Items are grouped by theme and roughly ordered by impact. Anything that requires Xcode project-file edits I can't make from the agent (target settings, capabilities, supported platforms) is marked **[manual]**.

## Blocking the basic happy path

- [ ] **[manual]** Tick **App Sandbox → Outgoing Connections (Client)** for the `coderpad` target. Without this, every API call fails with `NSURLErrorDomain -1003`.
- [ ] **[manual]** Rotate the API key that was pasted into chat earlier (it's in git history of the conversation, not the repo).

## Onboarding

- [ ] In Settings → Accounts, add a small banner with the "Get an API key" link (already in the editor sheet) plus the latest scopes the key needs.
- [ ] Validate keys not just for *can-reach-org* but also surface which scopes are missing if a 403 comes back from any endpoint.

## Data freshness & navigation

- [x] Auto-refresh pads list every 45s (questions every 90s). Gated by `scenePhase == .active`: paused when window isn't foregrounded.
- [x] Show a "last fetched X ago" indicator near the reload button (pads, questions).
- [x] Persist last-selected section per account.
- [x] Pinned pads — star button on each row, pinned pads float to top, scoped per account.
- [x] Diff highlights when reloading: blue dot on the avatar of any pad whose `updated_at` changed (or that's new) since the last refresh.
- [ ] Bias auto-refresh toward `state == "started"` pads (currently refreshes the whole list).

## Search & filtering

- [x] Filters in pads (state, language, owner, team, type) and questions (language, owner, take-home, status).
- [x] Searchable owner filter (popover with text field).
- [ ] Date-range filters (created / updated).
- [ ] Save searches as named views ("Live pads, my team, today").
- [ ] Spotlight integration via Core Spotlight so pads + questions are findable system-wide.

## Write paths

- [x] POST `/api/pads/` — create.
- [x] PUT `/api/pads/` — update title / language / owner / private / execution from an Edit sheet on pad detail.
- [x] POST `/api/questions/` — create from a New Question sheet (title, language, type, take-home, description, candidate instructions, solution).
- [x] PUT `/api/questions/:id` — edit from a sheet on the detail view (pencil button).
- [x] DELETE `/api/questions/:id` — with a confirmation dialog on the detail view (trash button).
- [ ] Bulk actions on pads (end started pads, mark private).

## Pad detail polish

- [x] In-pad code preview: show the active environment's `contents` in a monospaced scrollable card with copy button.
- [x] Events timeline grouping: consecutive `typed`/`edited`/`ran` events by the same user collapse to one row with `×N` chip and date range.
- [ ] Syntax highlighting for the code preview (CodeEditor / TextKit2).
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

- [x] VoiceOver labels on filter chips, stat tiles, pin button, and the event timeline (each event is `combine`d into a single accessible element with kind/count/user/time).
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

- [x] Periodic key health check: `AccountHealthMonitor` calls `/api/organization` every 30 minutes; an orange banner at the top of the window appears if the key returns 401/403, with Open Settings / Recheck buttons.
- [ ] Option to require Touch ID before revealing a saved key in Settings.
- [ ] Audit the Keychain item's access group; currently uses the default Generic Password class.

## App Store submission

### Blockers — must be resolved before submitting

- [ ] **Trademark / naming.** "CoderPad" is a registered trademark of CoderPad Inc. Apple App Review *will* reject (guideline 5.2.5) unless you have written permission from them. Pick one of:
    - Get written permission from CoderPad Inc. (best if you might partner with them).
    - Rename the app (e.g. "PadDeck", "InterviewPad", "DevInterview Browser"). Marketing copy and screenshots can still say "for CoderPad interviews".
- [ ] **Bundle identifier.** Currently `ptn.coderpad`. Replace with a reverse-domain ID under a domain *you* own (e.g. `com.adamdangoor.coderpad-mac`). Must be unique and stable across versions.
- [ ] **Paid Apple Developer Program membership** ($99/year). Required for App Store distribution; the existing "Personal Team" used for local Debug builds won't ship.
- [ ] **[manual]** In Signing & Capabilities, set Team to your paid team and switch the Release configuration to "Mac App Store Distribution" provisioning.

### Privacy

- [ ] **`PrivacyInfo.xcprivacy` manifest** at `coderpad/coderpad/PrivacyInfo.xcprivacy`. List:
    - `NSPrivacyTracking = false`
    - `NSPrivacyTrackingDomains = []`
    - `NSPrivacyCollectedDataTypes`: empty (the app only stores the user's own API key locally; no analytics, no upload).
    - `NSPrivacyAccessedAPITypes`: `NSPrivacyAccessedAPICategoryUserDefaults` (we read `UserDefaults` for the current account id / section), and `NSPrivacyAccessedAPICategoryFileTimestamp` only if you add file APIs later.
- [ ] **App Store Connect privacy nutrition labels** that match the manifest: no data collected, no third-party SDKs.
- [ ] **Privacy policy URL.** A short single-page policy hosted on GitHub Pages or similar. Required field even when you collect nothing.
- [ ] **Account deletion isn't applicable** (we don't sign users up — they paste a CoderPad key). Document this in the review notes.

### Code & build configuration

- [ ] Update **MARKETING_VERSION** and **CURRENT_PROJECT_VERSION** with each upload. Build number must monotonically increase per version.
- [ ] **MACOSX_DEPLOYMENT_TARGET** currently `26.4` — must match what App Review's hardware can run. Pick a real deployment target that today's App Review machines support (probably 14.0 unless you specifically need 26.x features).
- [ ] **Hardened runtime** enabled (off by default for Debug, required for Distribution).
- [ ] **App Sandbox** with these capabilities:
    - `com.apple.security.app-sandbox = true` ✅
    - `com.apple.security.network.client = true` ✅ (already needed for the API)
- [ ] No private API usage. (We don't; just sanity-check after any future refactor.)
- [ ] **Notarization** is automatic for App Store submissions, but if you also ship a non-App-Store DMG (see Distribution above), notarize via `notarytool`.
- [ ] **Asset catalog completeness**: AppIcon set ✅. Add Accent color if the system one isn't desired.

### App Store Connect listing

- [ ] App name (≤30 chars).
- [ ] Subtitle (≤30 chars). e.g. "Browse and manage interview pads".
- [ ] Promotional text (≤170 chars).
- [ ] Description (≤4000 chars). Include features, requires an existing CoderPad account, free to download.
- [ ] Keywords (≤100 chars total, comma separated).
- [ ] Support URL (linkable to a GitHub Issues page).
- [ ] Marketing URL (optional — the GitHub repo works).
- [ ] **Screenshots**: macOS requires 2880 × 1800 (or 1280 × 800) — at least one. Recommend 5: pad list, pad detail, in-window browser, organization view, settings.
- [ ] App preview video (optional, 15–30 s).
- [ ] Primary + secondary category: Developer Tools / Productivity.
- [ ] Age rating: 4+ (no objectionable content).
- [ ] Copyright line.
- [ ] Localizations: at least `en-US`. Add others later.

### Review-friendly details

- [ ] **Demo credentials in App Review notes**: tell the reviewer to flip the build to a Debug build for "Try Demo" — or, more practically, leave a *Release-safe* sample API key with read-only scope for review. Without it, Review can't see past the empty state.
- [ ] **Reviewer instructions**: explain that the app is a thin client over the public CoderPad API, the user provides their own key, and that keys are stored only in the local Keychain.
- [ ] **Avoid HIG violations**: no fake system UI, no copy-paste of standard alerts, no fake App Store / IAP UI. (Currently clean.)

### Releases

- [ ] Tag commits with semver (e.g. `v1.0.0`) and use the GitHub Releases page for release notes.
- [ ] Hook the existing GitHub Actions workflow to also produce a Release `.app` artifact on tag pushes (separate from Mac App Store flow).
- [ ] Set up Sparkle (or `SUUpdater`) for the non-App-Store builds (App Store builds update via the store).
- [ ] Add a small "What's New" sheet on first launch after an update.

### Polish before first submission

- [ ] Verify the app works *without* the network entitlement and shows a useful error rather than spinning forever.
- [ ] First-run UX with a real key: time-to-pads under 3 seconds for an org with ~100 pads.
- [ ] Memory profile during an extended Pads → Detail → Browser session.
- [ ] Verify VoiceOver pass on the pad list and detail view.
- [ ] Run Xcode's Accessibility Inspector audit; resolve any P0/P1 findings.
