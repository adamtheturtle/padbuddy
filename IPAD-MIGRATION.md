# iPad app migration

Goal: ship PadBuddy on iPad (full-parity intent) from the existing macOS-only target,
as **one multiplatform target** (macOS + iPad), not a second target. AppKit-only code is
guarded behind `#if os(macOS)`; iPad gets SwiftUI-native equivalents.

## Status

Source-side foundation is in place and is **macOS-safe by construction** (every change is
either a `#if os(macOS)` guard — always true on the macOS build, so macOS sees identical
code — or a pure-navigation refactor verified clean before an unrelated DerivedData issue
appeared). The iPad build itself is **blocked on three project-configuration changes that
only you can make in Xcode** — there is no Claude tool to change build settings / add a
destination, and editing `project.pbxproj` directly is disallowed (it can crash Xcode).

## You must do these 3 things in Xcode (≈3 min)

These were each confirmed necessary by an actual `xcodebuild` run.

1. **Add the iPad destination.** Project → `coderpad` target → **General** →
   **Supported Destinations** → **＋** → **iPad** (keep Mac). Set iPadOS deployment to
   **18.0** if asked. Without this, the scheme offers only macOS destinations and
   `xcodebuild`/Xcode reject every iOS destination *before compiling*.

2. **Make the Sparkle link macOS-only.** Sparkle's package is `platforms: [.macOS]`, and
   the `coderpad` target links it unconditionally, so an iOS build fails at the link step.
   `coderpad` target → **General** → **Frameworks, Libraries, and Embedded Content** →
   select **Sparkle** → set its **platforms filter** (the small "filter"/platforms control
   on the row) to **macOS** only. (Source already guards all Sparkle *usage* with
   `#if canImport(Sparkle)`, so no code change is needed — only the link filter.)

3. **Keep the widget out of iPad builds.** `RecentPadsWidget` imports AppKit, so it stays
   Mac-only. `coderpad` target → **Build Phases** → **Embed Foundation Extensions** → set
   the `RecentPadsWidgetExtension.appex` row's platform filter to **macOS**. Do the same
   for the widget under **Dependencies** if listed. Leave the `RecentPadsWidgetExtension`
   target's own Supported Destinations as Mac-only.

Then select an **iPad Pro 13" simulator** and build. Expect a wall of "X is unavailable in
iOS" AppKit errors across the files listed below — that is the expected next step, and the
compiler-driven cleanup is straightforward source work from there.

## Source work already done (committed intent, macOS-green)

- **`coderpadApp.swift`** — entry point split per platform: `AppDelegate`, the `--mcp`
  stdio-server branch, `@NSApplicationDelegateAdaptor`, the whole macOS scene graph
  (`Window` + per-window `WindowGroup`s + `Settings` + `MenuBarExtra`) and the menu
  `.commands` are behind `#if os(macOS)`. iPad gets an `iOSScenes` `WindowGroup` hosting
  the same `ContentView`, with the shared Spotlight-continuation and `coderpad://`
  deep-link handling.
- **`AppNavigation.swift`** — `routeNewPad(account:seedQuestionID:)` moved here (pure
  navigation, no AppKit) so every platform shares it. Callers in `InterviewTemplates.swift`
  and the deep-link handler updated; the macOS-only `AppDelegate.routeNewPad` removed.
- **Whole-file `#if os(macOS)` guards** (macOS-only, no iPad analog needed yet):
  `AppDelegate+NewPad.swift`, `AboutPanel.swift`, `ServicesProvider.swift`,
  `UITestingWindow.swift`, `MenuBarView.swift`, `MenuBarView+Logic.swift`,
  `coderpadApp+Commands.swift`.

## Remaining source work (do this with the iPad compiler after the 3 steps above)

Drive it off the build errors. Two buckets among the ~33 remaining AppKit files:

**A. Cross-platform utilities — keep the type, guard the AppKit body, add an iOS path:**
`AppActivator` (NSApp activate → no-op/`UIApplication` on iOS), `DockBadge` (NSDockTile →
no-op or `UIApplication.shared.applicationIconBadgeNumber`), `PadUpdateNotifier`
(UNUserNotificationCenter is cross-platform; only the badge auth/NSApp bits are macOS),
`SyntaxHighlighting` (NSColor → UIColor via a typealias), `WhiteboardImage`
(NSImage → UIImage), `DocumentPrinter` (NSPrintOperation → `UIPrintInteractionController`).

**B. Shared SwiftUI views with AppKit chrome — guard the chrome, give iPad a native list/detail:**
`ContentView+SplitChrome` / `+MainSplit` / `+AccountFooter` (NSViewRepresentable window
chrome → drop on iPad; `NavigationSplitView` already adapts), the `FastList`/NSTableView
list paths in `PadsView+Sidebar`, `QuestionsView+List`, `MergedPadsView+List`,
`MergedQuestionsView+List` (FastList is macOS NSTableView-backed — iPad needs a SwiftUI
`List`/`Table` equivalent), `*+ContextMenu` (`.contextMenu` is cross-platform; NSMenu bits
are not), `PadBrowser`/`PadBrowser+Views` (WKWebView host → `WebView`/`UIViewRepresentable`
on iPad), `PadDetailView+SaveCode` (NSSavePanel → `.fileExporter`), `CommandPalette`,
`PadCodePreview`/`+Card`, `DesignSystem+PullToRefresh` (iOS has native `.refreshable`),
`FavoritesDrag`, `MCPClientInstall`, `SettingsView+Models`, `ScreenTestDetailView`.

iPad-specific surfaces to add for parity: in-app Settings screen (no `Settings` scene on
iOS), and iPad multi-window via `WindowGroup(for:)` if desired (Stage Manager).

## Environment note

The shared DerivedData was found poisoned (`FastList.swiftmodule ... built for incompatible
target`) — symptomatic of a bare `xcodebuild`/Xcode-27-beta build writing into the default
DerivedData that the stable Xcode 26.5 then can't read. If Xcode shows module-incompatible
errors unrelated to source, clean DerivedData (or that module) and rebuild under stable Xcode.
