//
//  coderpadApp.swift
//  coderpad
//

import AppKit
import CoreSpotlight
import SwiftUI

let copyrightLine = "Copyright © 2026 Adam Dangoor"

/// Shows the app's custom About panel, populated with version, build, credits,
/// and copyright. Shared by the app menu and the menu-bar extra so both surface
/// the same information.
func showAboutPanel() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    AppActivator.bringToFront()
    NSApp.orderFrontStandardAboutPanel(options: [
        NSApplication.AboutPanelOptionKey.applicationName: "CoderPad",
        NSApplication.AboutPanelOptionKey.applicationVersion: version,
        NSApplication.AboutPanelOptionKey.version: "Build \(build)",
        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyrightLine
    ])
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Backs the "Open Pad in CoderPad" macOS Service; retained for the app's
    /// lifetime so `NSApp.servicesProvider` keeps a live target.
    private let servicesProvider = ServicesProvider()

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_: Notification) {
        // Carry an existing "Hide Dock icon" choice into the new presence preference,
        // then honor it from the moment the app launches.
        GeneralSettings.migratePresenceIfNeeded()
        GeneralSettings.applyDockVisibility()
        // Carry an old on/off Dock-badge choice into the new scope preference (#399),
        // then seed the badge from whatever pads are already cached; it refreshes again
        // as each account's list loads.
        DockBadge.migrateScopeIfNeeded()
        DockBadge.refresh()
        // Keep the current account's pads fresh on a timer even when no window is open
        // and the menu is never clicked — the one state where nothing else fetches.
        // Writing to PadsCacheStore cascades to the widget snapshot and Dock badge.
        PadsBackgroundRefresher.shared.start()
        // Watch network reachability so the app can drop into a read-only mode while
        // CoderPad is unreachable, surfacing an offline banner and disabling edits (#321).
        NetworkMonitor.shared.start()
        // Become the notification-center delegate so taps on pad-update alerts route
        // back into the app. Posting itself is opt-in (see `PadUpdateNotifier`).
        PadUpdateNotifier.shared.register()
        // Offer the "Open Pad in CoderPad" Service (declared in Info.plist) to other
        // apps. NSUpdateDynamicServices refreshes the registry so the item appears
        // without needing a log-out/in during development.
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
    }

    /// The menu shown when right-clicking the Dock icon. Offers the same quick
    /// actions as the app's New menu, routed through the app's own `coderpad://`
    /// deep links so they work — and reopen the main window — whether or not a
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

@main
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

    var body: some Scene {
        WindowGroup("CoderPad", id: "main") {
            ContentView()
                // Width floor is owned by `MainSplit`, derived from the live column
                // minimums (and enforced via the sidebar's auto-collapse) rather
                // than a hardcoded number here.
                .frame(minHeight: 540)
                .preferredColorScheme(appearance.colorScheme)
                // Open the pad/question behind a tapped Spotlight result.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }

                    if let padID = SpotlightIndexer.padID(fromItemIdentifier: id) {
                        AppNavigation.shared.openPad(id: padID)
                    } else if let ref = SpotlightIndexer.questionRef(fromItemIdentifier: id) {
                        // Switch to the owning account first so the right org's
                        // question is selected — per-org ids collide across accounts (#378).
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
            PrintCommands()
            // The system's Show/Hide and Customize Toolbar commands. Every section
            // and detail toolbar is a customizable `.toolbar(id:)` with stable item
            // ids, so "Customize Toolbar…" is enabled and the whole window toolbar
            // can be rearranged.
            ToolbarCommands()
            ViewCommands()
            PadCommands()
            QuestionCommands()
            WindowCommands()
        }

        padBrowserScene
        questionScene
        padScene

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

    /// Double-clicking a question row opens its detail here, in its own window —
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

    /// Double-clicking a pad row opens its native detail here, in its own window —
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
            Button("About CoderPad") { showAbout() }
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
            // Backs the "New Pad" control (Control Center / menu bar), the Dock menu,
            // and the widget button: switch to Pads and open the create sheet, the
            // same flow as ⌘N. The widget button may also pin an account and seed a
            // favourite question; switch to that account first (so the seeded id,
            // which is only unique within its org, resolves against the right account)
            // then queue the seed for the create sheet.
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let accountID = components?.queryItems?.first(where: { $0.name == "account" })?.value,
               let uuid = UUID(uuidString: accountID),
               AccountsStore.shared.accounts.contains(where: { $0.id == uuid }) {
                AccountsStore.shared.showAllAccounts = false
                AccountsStore.shared.currentAccountID = uuid
            }
            let seedQuestionID = components?.queryItems?
                .first(where: { $0.name == "question" })?.value.flatMap(Int.init)
            AppNavigation.shared.showPads(PadsRequest(startCreating: true, seedQuestionID: seedQuestionID))

        case "new-question":
            AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))

        default:
            break
        }
    }

    /// Moves the visible section forward (`+1`) or back (`-1`) through the fixed
    /// section order, wrapping at the ends. Backs the Go menu's Next/Previous items.
    private func cycleSection(by delta: Int) {
        let order: [AppSection] = [.pads, .questions, .organization]
        let current = AppNavigation.shared.section
        let index = order.firstIndex(of: current) ?? 0
        let count = order.count
        let next = order[((index + delta) % count + count) % count]
        AppNavigation.shared.show(next)
    }

    private func showAbout() {
        showAboutPanel()
    }
}
