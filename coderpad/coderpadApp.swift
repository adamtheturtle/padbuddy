//
//  coderpadApp.swift
//  coderpad
//

import AppKit
import CoreSpotlight
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Backs the "Open Pad in CoderPad" macOS Service; retained for the app's
    /// lifetime so `NSApp.servicesProvider` keeps a live target.
    private let servicesProvider = ServicesProvider()

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Honor the presence preference from the moment the app launches. The migration
        // that may set it ran earlier in `AppLaunch.run()` (from `CoderpadApp.init()`).
        // This stays here, not in `AppLaunch`, because it sets `NSApp`'s activation
        // policy and must run after the app has finished launching.
        GeneralSettings.applyDockVisibility()
        // Offer the "Open Pad in CoderPad" Service (declared in Info.plist) to other
        // apps. NSUpdateDynamicServices refreshes the registry so the item appears
        // without needing a log-out/in during development. Stays here because it wires
        // up the delegate-retained `servicesProvider`.
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
        registerNewPadRequestObserver()
    }

    /// Perform any New Pad request the widget or Control Center button recorded. They
    /// can't open the app's custom URL scheme (`OpenURLIntent` is https-only) or use a
    /// `Link` on the small widget, so `CreatePadIntent` writes the request to the App
    /// Group and brings the app forward; this consumes it once the app is active
    /// (#456, #485). Reading on activation (rather than via `onOpenURL`) also covers a
    /// cold launch, since the app activates after launching.
    func applicationDidBecomeActive(_: Notification) {
        // When driving the seeded demo for screenshots/UI tests, grow the main window
        // to fill the screen so captures show the full three-column layout (and meet
        // the App Store's minimum screenshot size, #62) rather than a cold-launch
        // sliver. Test-only: gated on `-uiTesting`, so it never affects real users.
        UITestingWindow.sizeToScreenIfNeeded()

        Self.drainPendingNewPad()
    }

    /// The menu shown when right-clicking the Dock icon. Offers the same quick
    /// actions as the app's New menu, routed through the app's own `coderpad://`
    /// deep links so they work - and reopen the main window - whether or not a
    /// window is currently open. macOS appends its standard items (Show All Windows,
    /// Quit, …) below these.
    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        addDockItem(to: menu, title: "New Pad", urlString: "coderpad://new-pad")
        addDockItem(to: menu, title: "New Question", urlString: "coderpad://new-question")
        menu.addItem(.separator())
        addDockItem(to: menu, title: "Show Pads", urlString: "coderpad://pads")
        addDockItem(to: menu, title: "Show Questions", urlString: "coderpad://questions")
        return menu
    }

    private func addDockItem(to menu: NSMenu, title: String, urlString: String) {
        let item = NSMenuItem(title: title, action: #selector(openDockURL(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = urlString
        menu.addItem(item)
    }

    @objc private func openDockURL(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }

        AppActivator.bringToFront()
        // Route through LaunchServices to our own scheme: this both delivers the deep
        // link and brings up a main window when none is open, the same path widget
        // taps use.
        URLOpener.open(url)
    }
}

/// Process entry point. Before the SwiftUI app starts, check for the `--mcp` flag: in
/// that mode the process is a headless Model Context Protocol server (#402), driven over
/// stdio by an MCP client, and never shows any UI. Otherwise it launches the app as
/// usual by calling ``CoderpadApp/main()``.
@main
enum AppEntryPoint {
    static func main() {
        if CommandLine.arguments.contains(MCPServer.commandLineFlag) {
            // Resolve the accounts here, on the main actor, since `Account` is main-actor
            // isolated; the server itself then runs nonisolated over stdio.
            MCPServer.runUntilExit(directory: MCPAccountLoader.directory())
        }
        CoderpadApp.main()
    }
}

struct CoderpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Observed so the File ▸ New commands disable while the app is offline (#321),
    /// matching the in-window New buttons and the menu-bar extra.
    @State private var network = NetworkMonitor.shared

    /// Drives the app-wide light/dark override; nil follows the system appearance.
    @AppStorage(GeneralSettings.Key.appearance) private var appearance: AppAppearance = .system

    /// Whether the app shows in the Dock, the menu bar, or both. Gates the menu-bar
    /// extra below so "Dock only" removes the menu-bar icon.
    @AppStorage(GeneralSettings.Key.presence) private var presence: AppPresence = .dockAndMenuBar

    init() {
        // Run the app-global launch seeding once at process launch. `init()` fires
        // before the delegate's `applicationDidFinishLaunching(_:)` and regardless of
        // which scene opens - so this also runs in Dock-only / menu-bar-only modes
        // where no window appears and a scene `.task` would never fire (#286).
        AppLaunch.run()
    }

    var body: some Scene {
        // A single, unique main window (`Window`, not `WindowGroup`): opening "main"
        // again - from the menu bar's Add Account, the Dock icon, or "Open Main
        // Window" - focuses the existing window instead of spawning a duplicate (#459).
        // The app still survives closing it (windowless menu-bar mode) because
        // `applicationShouldTerminateAfterLastWindowClosed` returns false.
        Window("PadBuddy", id: "main") {
            ContentView()
                // Width floor is owned by `MainSplit`, derived from the live column
                // minimums (and enforced via the sidebar's auto-collapse) rather
                // than a hardcoded number here.
                .frame(minHeight: 540)
                // Screenshot-only Dynamic Type override (`-uiTestingTextSize <name>`):
                // captures the marketing shots with larger, more legible UI text. Nil
                // for real users, so their own accessibility text size is honored.
                .modifier(ScreenshotTextSize(size: Self.screenshotTextSize))
                .preferredColorScheme(appearance.colorScheme)
                // Open the pad/question behind a tapped Spotlight result.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

                    if let padID = SpotlightIndexer.padID(fromItemIdentifier: id) {
                        AppNavigation.shared.openPad(id: padID)
                    } else if let ref = SpotlightIndexer.questionRef(fromItemIdentifier: id) {
                        // Switch to the owning account first so the right org's
                        // question is selected - per-org ids collide across accounts (#378).
                        // Only if it still exists; a removed account's items are cleared too.
                        if AccountsStore.shared.accounts.contains(where: { $0.id == ref.account }) {
                            AccountsStore.shared.currentAccountID = ref.account
                        }
                        AppNavigation.shared.showFavoriteQuestion(id: ref.id)
                    }
                }
                // Open a pad tapped in the Recent Pads widget (coderpad://pad/<id>).
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1100, height: 720)
        .commands {
            appCommands
            FindCommands()
            NewPadFromQuestionCommands()
            PrintCommands()
            // The system's Show/Hide and Customize Toolbar commands. Every section
            // and detail toolbar is a customizable `.toolbar(id:)` with stable item
            // ids, so "Customize Toolbar…" is enabled and the whole window toolbar
            // can be rearranged.
            ToolbarCommands()
            ViewCommands()
            PadCommands()
            QuestionCommands()
            TemplateCommands()
            WindowCommands()
        }

        padBrowserScene
        questionScene
        padScene
        screenTestScene
        mcpActivityScene

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }

        menuBarScene
    }

    /// A pad opened in its own window (`coderpad://pad/<id>` or the Open action).
    /// Split out of `body` so each scene type-checks independently and the main
    /// scene builder stays under the long-body diagnostic budget.
    private var padBrowserScene: some Scene {
        // swiftformat:disable:next unusedArguments
        WindowGroup("Pad Browser", id: "pad-browser", for: URL.self) { $url in
            if let url {
                PadBrowserView(url: url)
                    .frame(minWidth: 900, minHeight: 700)
                    .navigationTitle(url.host ?? "Pad")
                    .preferredColorScheme(appearance.colorScheme)
            } else {
                // The system can restore this window without a persisted URL; show a
                // placeholder rather than a blank, zero-content window.
                ContentUnavailableView("No Pad", systemImage: "macwindow",
                                       description: Text("Open a pad to view it here."))
                    .frame(minWidth: 900, minHeight: 700)
                    .preferredColorScheme(appearance.colorScheme)
            }
        }
    }

    /// Double-clicking a question row opens its detail here, in its own window -
    /// the native-detail counterpart to opening a pad in the `pad-browser` window
    /// (#292). Keyed by a lightweight id so it survives state restoration.
    private var questionScene: some Scene {
        // swiftformat:disable:next unusedArguments
        WindowGroup("Question", id: "question", for: QuestionWindowID.self) { $value in
            QuestionWindow(value: value)
                .frame(minWidth: 600, minHeight: 560)
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    /// Double-clicking a pad row opens its native detail here, in its own window -
    /// the pad counterpart to ``questionScene`` (#354). Keyed by a lightweight id
    /// so it survives state restoration.
    private var padScene: some Scene {
        // swiftformat:disable:next unusedArguments
        WindowGroup("Pad", id: "pad", for: PadWindowID.self) { $value in
            PadWindow(value: value)
                .frame(minWidth: 600, minHeight: 560)
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    /// A Screen test session's report opened in its own window, from the tests list's
    /// "Open in New Window" action / double-click (#474). Keyed by a lightweight id so
    /// it survives state restoration.
    private var screenTestScene: some Scene {
        // swiftformat:disable:next unusedArguments
        WindowGroup("Test Session", id: "screen-test", for: ScreenTestWindowID.self) { $value in
            ScreenTestWindow(value: value)
                .frame(minWidth: 600, minHeight: 560)
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    /// The menu-bar extra. The system can flip `isInserted` to false if the user
    /// drags the icon out of the menu bar; mirror that back into the preference so
    /// the change sticks and the Settings picker stays honest. Removing the icon
    /// switches to "Dock only" (revealing the Dock icon if it was hidden, so the app
    /// never ends up with no visible affordance); re-inserting it restores a
    /// menu-bar mode.
    private var menuBarScene: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { presence.showsMenuBarIcon },
            set: { inserted in
                guard inserted != presence.showsMenuBarIcon else { return }

                presence = inserted
                    ? (presence.showsDockIcon ? .dockAndMenuBar : .menuBarOnly)
                    : .dockOnly
                GeneralSettings.applyDockVisibility()
            }
        )) {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About PadBuddy") { showAbout() }
        }
        // "Check for Updates…" sits just below About, its conventional home. The
        // item only appears once the Sparkle package is linked (#28); without it
        // this group is empty and adds nothing.
        CommandGroup(after: .appInfo) {
            #if canImport(Sparkle)
                CheckForUpdatesButton()
            #endif
        }
        CommandGroup(replacing: .newItem) {
            Button("New Pad…") {
                AppNavigation.shared.showPads(PadsRequest(startCreating: true))
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(network.isOffline)
            Button("New Question…") {
                AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(network.isOffline)
            Divider()
            Button("Open Pad by URL…") {
                AppRouter.requestOpenPadByURL()
            }
            .keyboardShortcut("o", modifiers: [.command])
            Divider()
            Button("Reload") {
                AppRouter.requestReload()
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        CommandMenu("Go") {
            // The command palette lives here, not in File: it's the "go to anything"
            // entry point, so the Go menu is where users look for it (#533).
            Button("Go to Anything…") {
                AppRouter.requestCommandPalette()
            }
            .keyboardShortcut("k", modifiers: [.command])
            Divider()
            Button("Pads") { post(.pads) }.keyboardShortcut("1", modifiers: [.command])
            Button("Questions") { post(.questions) }.keyboardShortcut("2", modifiers: [.command])
            Button("Organization") { post(.organization) }.keyboardShortcut("3", modifiers: [.command])
            Divider()
            Button("Next Section") { cycleSection(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Section") { cycleSection(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
            Link("Get API Key", destination: CoderPadLinks.apiSettings)
            Divider()
            Link("Send Feedback…", destination: CoderPadLinks.feedbackMailto)
        }
    }

    private func post(_ section: AppSection) {
        AppNavigation.shared.show(section)
    }

    /// Routes a `coderpad://` deep link from the widget. `coderpad://pad/<id>` opens
    /// that pad in the in-app browser; `coderpad://pads` just brings the Pads list
    /// forward. Reuses the same durable navigation as the Spotlight and intent paths.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "coderpad" else { return }

        switch url.host {
        case "pad":
            let id = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !id.isEmpty { AppNavigation.shared.openPad(id: id) }

        case "pads":
            AppNavigation.shared.show(.pads)

        case "questions":
            AppNavigation.shared.show(.questions)

        case "new-pad":
            // Backs the Dock menu's New Pad item (the widget and Control Center buttons
            // now route through `CreatePadIntent`/`applicationDidBecomeActive` instead,
            // since they can't open this custom scheme). Switch to Pads and open the
            // create sheet, the same flow as ⌘N - optionally pinning an account and
            // seeding a favourite question, via the shared `routeNewPad`.
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let account = components?.queryItems?.first(where: { $0.name == "account" })?.value
            let seedQuestionID = components?.queryItems?
                .first(where: { $0.name == "question" })?.value.flatMap(Int.init)
            AppDelegate.routeNewPad(account: account, question: seedQuestionID)

        case "new-question":
            AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))

        default:
            break
        }
    }

    /// Moves the visible section forward (`+1`) or back (`-1`) through the currently
    /// navigable section order, wrapping at the ends. Backs the Go menu's
    /// Next/Previous items. Uses `AppSection.navigable` - the same source as the
    /// sidebar - so Quota and Screen are included whenever they're shown (#481);
    /// the old hardcoded `[.pads, .questions, .organization]` skipped them.
    private func cycleSection(by delta: Int) {
        let order = AppSection.navigable
        guard !order.isEmpty else { return }

        let current = AppNavigation.shared.section
        let index = order.firstIndex(of: current) ?? 0
        let count = order.count
        let next = order[((index + delta) % count + count) % count]
        AppNavigation.shared.show(next)
    }

    private func showAbout() {
        showAboutPanel()
    }

    /// The Dynamic Type size to pin for marketing-screenshot capture, read from
    /// `-uiTestingTextSize <name>` (e.g. `accessibility1`). Returns nil outside that
    /// mode so real users' system text size is always honored.
    static var screenshotTextSize: DynamicTypeSize? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-uiTestingTextSize"), index + 1 < args.count else {
            return nil
        }
        switch args[index + 1] {
        case "large": return .large
        case "xLarge": return .xLarge
        case "xxLarge": return .xxLarge
        case "xxxLarge": return .xxxLarge
        case "accessibility1": return .accessibility1
        case "accessibility2": return .accessibility2
        case "accessibility3": return .accessibility3
        default: return nil
        }
    }
}

/// Applies a Dynamic Type override only when one is set; without this, pinning a
/// non-optional size would stop honoring a real user's accessibility text setting.
private struct ScreenshotTextSize: ViewModifier {
    let size: DynamicTypeSize?

    func body(content: Content) -> some View {
        if let size {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}
