# Contributing

## Fast local builds

The project uses Xcode's JSON configuration file, `PadBuddy.xcodeproj/project.xcproj`.
Open it with Xcode 27 or later; changing the project file format requires Xcode 27.2 or later.
CI generates a temporary legacy project for the macOS 15 test job that uses Xcode 26.

For the normal edit/build loop on macOS, use:

```sh
./scripts/build-fast.sh
```

This uses the checked-in `Package.resolved`, disables coverage instrumentation, and skips App Intents metadata extraction.
Use a normal Xcode build after changing Shortcuts, Focus filters, or widget intents so Xcode regenerates that metadata.
Archives and release builds always use the full build path.

## Visual checks with demo data

For screenshots and visual checks on macOS, run:

```sh
bash scripts/run-demo.sh
```

The command builds with the project's normal signing settings and runs a new instance with `-uiTesting`.
It stays attached to that process until you quit the demo.
The demo skips restoration of previous windows and keeps the default window size.
That launch flag seeds an in-memory demo account and skips credential persistence, so visual checks do not read your saved API keys or trigger credential-access prompts.
The build lives in `.context/DerivedData-demo/`; set `DEMO_DERIVED_DATA_PATH` to use another location.
Extra arguments are passed to the app: `bash scripts/run-demo.sh -uiTestingNoAccounts` opens the empty account-setup state.
When launching through another tool, pass `-uiTesting` explicitly.

Ordinary app launches use saved accounts and can require Keychain authorization after a Debug rebuild.
Use them when checking behavior that requires real credentials.
Typing the `demo` magic key in an ordinary launch still loads the normal credential store first; use the launch flag for isolated visual checks.

## Preflight before pushing

Run the complete local confidence check with one command:

```sh
./scripts/preflight.sh
```

The check covers the pinned package graph, SwiftLint and SwiftFormat, a macOS build, the Fast test plan, and staged and unstaged patches for whitespace errors.
Xcode stays quiet unless it has a diagnostic to report.
Concise timing and warning counts from its result bundle appear in the output.
Inspectable result bundles are written under `.context/preflight/`.

## Adopting owned package releases

Keep individual bug reports in the package that owns the bug.
After publishing a package release, create one app-side adoption tracker for that release from Actions ▸ **Track package release**, listing all upstream issue URLs there.
The workflow is idempotent: rerunning it finds the existing `Adopt <package> <version>` issue instead of opening duplicates.
The same operation is available locally through `scripts/create-package-adoption-issue.sh`.

## Testing: keep the pyramid healthy

The test suite has three tiers, cheapest first.
**Default new coverage to the cheapest tier that can catch the regression**, so the suite stays fast and the expensive tier stays thin.

| Tier | Where | Cost | Use it for |
| --- | --- | --- | --- |
| Unit | `PadBuddyTests/` (e.g. `PadBuddyTests+Models.swift`, `PadBuddyTests+PadFiltering.swift`, `PadBuddyTests+PadListLogic.swift`, `PadBuddyTests+SearchInterpreter.swift`) | Milliseconds | Logic, decoding, filtering, search, error mapping. Anything with no view involved. |
| Render | `PadBuddyTests/DesignSystemRenderTests.swift` | Fast (no app launch) | View-level regressions. Rasterize a view with `ImageRenderer` and assert it produces a valid, non-zero image. |
| XCUITest | `PadBuddyUITests/` | A full cold app launch each | A thin smoke layer only: does it launch, does the list paint, can you navigate. |

### Prefer a render test to a UI test

`DesignSystemRenderTests` shows the cheap substitute for many UI tests: rather than booting the whole app to check a view behaves, render it in isolation via `ImageRenderer` and assert it rasterizes (doesn't crash, doesn't collapse to zero size).
This needs no third-party snapshot library and keeps nothing to re-record across OS or font-rendering changes.

```swift
let renderer = ImageRenderer(content: MyView(...))
renderer.scale = 2
#expect(renderer.nsImage?.size.width ?? 0 > 0)
```

### Reserve XCUITest for a smoke layer

Every XCUITest adds a cold launch, so the UI tier is where suite runtime creeps.
Resist adding more than the essentials — launch, first paint, basic navigation.
If a regression can be caught by a unit or render test, write that instead.

### Why

Fast feedback keeps the suite worth running on every change.
When a pull request reaches for a UI test, ask whether a unit or render test would prove the same thing in a fraction of the time, and point here.

Use the [Swift Testing](https://developer.apple.com/documentation/testing/) framework for unit and render tests, and `XCUIAutomation` for the UI smoke tier.

## Demo accounts: the `demo` and `baddemo` magic keys

The app ships with two sandbox accounts backed by an in-process mock server, so you can explore the full UI with no CoderPad API key and no network.
They are summoned by typing a magic word into a new account's **API Key** field rather than by any visible button:

| Type this key | You get | Use it for |
| --- | --- | --- |
| `demo` | A mock-data account (pads, questions, organization, quota, Screen) | Exploring the app, screenshots, first-run UX |
| `baddemo` | An account whose mock server answers 401 to every request | Exercising the revoked-key / unauthorized banner and error states |

To add one: Settings (⌘,) ▸ Accounts ▸ **Add Account**, type the word in the API Key field, and press Return (Validate).
Both keys are recognized in **every** build (Debug and Release), require no credentials, and send no data anywhere.

### How it works

- `Account.DemoMagicKey(typedKey:)` (`Accounts+Account.swift`) maps the typed word to a kind.
  The user-facing words are kept independent of each account's internal sentinel key (`Account.demo()` uses `"demo"`, `Account.demoBadKey()` uses `badKeyMockKey`), so the magic words can change without a stored-account migration.
- `AccountEditor.validate()` (`AccountEditor+Logic.swift`) intercepts a magic key before hitting the network: it calls `addDemoIfMissing()` / `addDemoBadKeyIfMissing()` (which dedupe an existing demo and make it active), then dismisses the editor.
- `Account.makeClient()` routes any `isMock` account to the in-process mock client, returning 401s for the bad-key demo.

### Why a magic key instead of a button

This replaced an earlier `wand.and.stars` menu whose "Bad API key" entry was `#if DEBUG`-gated (#549).
Folding demo creation into the normal key field keeps it Release-safe for first-run users and for **App Review**, which runs a Release build with no key and would otherwise see the empty "add a key" state.
The App Review notes in [`docs/app-store-listing.md`](docs/app-store-listing.md) direct the reviewer to type `demo`.
Because `baddemo` is now an undocumented magic key rather than a visible control, the bad-key demo is reachable in any build for testing without being surfaced to real users.

## Isolated core UI flows

Run `bash scripts/test-core-ui.sh` for account setup, demo browsing, section navigation, and browser handoff coverage.
The dedicated `CoreUI` plan selects only these interaction tests.
The script builds the app and its extensions with a `.uitesting` bundle-ID suffix and launches only the in-memory `-uiTesting` fixtures.
It does not terminate or reuse the normally installed PadBuddy application.
The suffix is empty for ordinary builds.
Pass additional xcodebuild options to the script when needed.
