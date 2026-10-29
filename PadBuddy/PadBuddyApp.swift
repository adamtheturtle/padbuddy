//
//  PadBuddyApp.swift
//  coderpad
//

import CoreSpotlight
import SwiftUI
#if os(macOS)
    import AppKit
    import Darwin
#endif

#if os(macOS)
    final class AppDelegate: NSObject, NSApplicationDelegate {
        /// Backs the "Open Pad in CoderPad" macOS Service; retained for the app's
        /// lifetime so `NSApp.servicesProvider` keeps a live target.
        private let servicesProvider = ServicesProvider()
        let widgetRequestObserverRegistration = WidgetRequestObserverRegistration()

        func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
            false
        }

        func applicationDidFinishLaunching(_: Notification) {
            // Honor the presence preference from the moment the app launches. The migration
            // that may set it ran earlier in `AppLaunch.run()` (from `PadBuddyApp.init()`).
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
        func applicationWillTerminate(_: Notification) {
            unregisterNewPadRequestObserver()
        }

        func applicationDidBecomeActive(_: Notification) {
            // When driving the seeded demo for screenshots/UI tests, grow the main window
            // to fill the screen so captures show the full three-column layout (and meet
            // the App Store's minimum screenshot size, #62) rather than a cold-launch
            // sliver. Test-only: gated on `-uiTesting`, so it never affects real users.
            UITestingWindow.sizeToScreenIfNeeded()

            Self.drainPendingNewPad()
        }

        /// The menu shown when right-clicking the Dock icon. Offers the same quick
        /// actions as the app's New menu, routed through the app's own `com.adamdangoor.padbuddy://`
        /// deep links so they work - and reopen the main window - whether or not a
        /// window is currently open. macOS appends its standard items (Show All Windows,
        /// Quit, …) below these.
        func applicationDockMenu(_: NSApplication) -> NSMenu? {
            let menu = NSMenu()
            addDockItem(to: menu, title: String(localized: "New Pad"),
                        urlString: "com.adamdangoor.padbuddy://new-pad")
            addDockItem(to: menu, title: String(localized: "New Question"),
                        urlString: "com.adamdangoor.padbuddy://new-question")
            menu.addItem(.separator())
            addDockItem(to: menu, title: String(localized: "Show Pads"),
                        urlString: "com.adamdangoor.padbuddy://pads")
            addDockItem(to: menu, title: String(localized: "Show Questions"),
                        urlString: "com.adamdangoor.padbuddy://questions")
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
            Task { await URLOpener.open(url) }
        }
    }
#endif

/// Process entry point. Before the SwiftUI app starts, check for the `--mcp` flag: in
/// that mode the process is a headless Model Context Protocol server (#402), driven over
/// stdio by an MCP client, and never shows any UI. Otherwise it launches the app as
/// usual by calling ``PadBuddyApp/main()``.
@main
enum AppEntryPoint {
    static func main() {
        #if os(macOS)
            if CommandLine.arguments.contains(MCPServer.healthCheckFlag) {
                let accountSet = MCPAccountLoader.accountSet()
                let result = MCPHealthCheck.evaluate(
                    enabled: UserDefaults.standard.bool(forKey: MCPServer.enabledDefaultsKey),
                    usableAccountCount: accountSet.accounts.count
                )
                FileHandle.standardOutput.write(Data(result.output.utf8))
                Darwin.exit(result.isUsable ? EXIT_SUCCESS : EXIT_FAILURE)
            }
            // The stdio MCP server mode (#402) is inherently a macOS command-line entry
            // point; iPadOS apps are never launched with a `--mcp` flag over stdio, so
            // this branch compiles out there.
            if CommandLine.arguments.contains(MCPServer.commandLineFlag) {
                // Resolve the accounts here, on the main actor, since `Account` is main-actor
                // isolated; the server itself then runs nonisolated over stdio.
                MCPServer.runUntilExit(accountSet: MCPAccountLoader.accountSet())
            }
        #endif
        // The unit-test host runs an inert placeholder app instead of the real one:
        // the live scene graph observes @AppStorage/@FocusedValue state, and a test
        // writing UserDefaults from its own thread re-evaluated the app/commands
        // bodies on that thread, where the dynamic MainActor check dereferenced the
        // test task's already-freed executor and crashed the host a few seconds
        // into every full-suite run (#978). UI tests are unaffected: they launch
        // the app as a separate process with no XCTest configuration in its
        // environment.
        if coderpadIsHostingUnitTests {
            UnitTestHostApp.main()
        } else {
            PadBuddyApp.main()
        }
    }
}

/// The inert app the unit-test host presents; see ``AppEntryPoint/main()``.
struct UnitTestHostApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbatim: "Hosting unit tests")
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

struct PadBuddyApp: App {
    #if os(macOS)
        @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #elseif os(iOS)
        @UIApplicationDelegateAdaptor(IPadQuickActionAppDelegate.self) var appDelegate
    #endif

    /// Observed so the File ▸ New commands disable while the app is offline (#321),
    /// matching the in-window New buttons and the menu-bar extra.
    @State var network = NetworkMonitor.shared
    /// Observed so the New Pad / New Question commands track whether there is an
    /// account to create under (#2323).
    @State var accounts = AccountsStore.shared

    /// Drives the app-wide light/dark override; nil follows the system appearance.
    /// Module-internal (not private) so the macOS scene graph, split into
    /// coderpadApp+MacScenes.swift for file length, can read it.
    @AppStorage(GeneralSettings.Key.appearance) var appearance: AppAppearance = .system

    /// Whether the app shows in the Dock, the menu bar, or both. Gates the menu-bar
    /// extra below so "Dock only" removes the menu-bar icon.
    @AppStorage(GeneralSettings.Key.presence) var presence: AppPresence = .dockAndMenuBar

    init() {
        // Run the app-global launch seeding once at process launch. `init()` fires
        // before the delegate's `applicationDidFinishLaunching(_:)` and regardless of
        // which scene opens - so this also runs in Dock-only / menu-bar-only modes
        // where no window appears and a scene `.task` would never fire (#286).
        AppLaunch.run()
    }

    var body: some Scene {
        #if os(macOS)
            macOSScenes
        #else
            iOSScenes
        #endif
    }

    // The platform scene graphs live in dedicated extension files (#580), each
    // gated by its own platform `#if`:
    //   - `macOSScenes` + the per-window scenes, `appCommands`, `showAbout`
    //     -> coderpadApp+MacScenes.swift
    //   - `iOSScenes` + `iPadSettingsSheet`
    //     -> coderpadApp+iOSScenes.swift

    func post(_ section: AppSection) {
        AppNavigation.shared.show(section)
    }

    func postIfNavigable(_ section: AppSection) {
        guard AppSection.navigable.contains(section) else { return }

        post(section)
    }

    /// Routes a `com.adamdangoor.padbuddy://` deep link from the widget. `com.adamdangoor.padbuddy://pad/<id>` opens
    /// that pad in the user's browser; `com.adamdangoor.padbuddy://pads` just brings the Pads list
    /// forward. Reuses the same durable navigation as the Spotlight and intent paths.
    func handleDeepLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(),
              ["com.adamdangoor.padbuddy", "coderpad"].contains(scheme) else {
            AppNavigation.shared.unsupportedDeepLink = url
            return
        }

        switch url.host?.lowercased() {
        case "pad":
            openPadDeepLink(url)

        case "pads":
            if let account = Self.accountID(fromDeepLink: url),
               AccountsStore.shared.accounts.contains(where: { $0.id == account }) {
                AccountsStore.shared.showAllAccounts = false
                AccountsStore.shared.currentAccountID = account
            }
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
            AppNavigation.shared.routeNewPad(account: account, seedQuestionID: seedQuestionID)

        case "new-question":
            AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))

        default:
            AppNavigation.shared.unsupportedDeepLink = url
        }
    }

    /// `com.adamdangoor.padbuddy://pad/<id>`. An `account` query names which account owns
    /// the id, so a same-slug pad on another custom server can't be opened instead
    /// (#2173). When the parameter is present but malformed or no longer configured,
    /// reject the link rather than falling back to another organization (#4660).
    private func openPadDeepLink(_ url: URL) {
        guard let id = Self.padID(fromDeepLink: url) else {
            AppNavigation.shared.unsupportedDeepLink = url
            return
        }

        let accountQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "account" }?.value
        guard let accountQuery else {
            AppNavigation.shared.openPad(id: id, account: nil)
            return
        }
        guard let owner = UUID(uuidString: accountQuery),
              AccountsStore.shared.accounts.contains(where: { $0.id == owner })
        else {
            AppNavigation.shared.unsupportedDeepLink = url
            return
        }

        AppNavigation.shared.openPad(id: id, account: owner)
    }

    static func padID(fromDeepLink url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              ["com.adamdangoor.padbuddy", "coderpad"].contains(scheme),
              url.host?.lowercased() == "pad",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        let segments = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.count == 2, segments[0].isEmpty,
              let id = String(segments[1]).removingPercentEncoding else { return nil }

        // Match the same ASCII pad-id rules used when the request is consumed so a
        // malformed link is rejected here (with Cannot Open Link) instead of clearing
        // navigation and then silently doing nothing (#4661).
        return PadIDValidation.normalize(id)
    }

    static func accountID(fromDeepLink url: URL) -> UUID? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "account" })?.value
            .flatMap(UUID.init(uuidString:))
    }

    /// Moves the visible section forward (`+1`) or back (`-1`), wrapping at the
    /// ends. Backs the Go menu's Next/Previous items. Queued as a request that the
    /// focused window resolves against its *own* section (per-window since #907)
    /// and the navigable order (Quota/Screen included whenever shown, #481).
    func cycleSection(by delta: Int) {
        AppNavigation.shared.cycleSection(by: delta)
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
/// Module-internal (not private) so the macOS scene graph in coderpadApp+MacScenes.swift
/// can apply it too.
struct ScreenshotTextSize: ViewModifier {
    let size: DynamicTypeSize?

    func body(content: Content) -> some View {
        if let size {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}
