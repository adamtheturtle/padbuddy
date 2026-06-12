//
//  coderpadApp.swift
//  coderpad
//

import SwiftUI
import AppKit

let copyrightLine = "Copyright © 2026 Adam Dangoor"

/// Shows the app's custom About panel, populated with version, build, credits,
/// and copyright. Shared by the app menu and the menu-bar extra so both surface
/// the same information.
func showAboutPanel() {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    let credits = NSAttributedString(
        string: """
A macOS client for the CoderPad Interview API.

Browse pads, questions, organization stats, and quota.
Multi-account, Keychain-backed, with a mock-data demo mode.
""",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
        ]
    )
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [
        NSApplication.AboutPanelOptionKey.applicationName: "CoderPad",
        NSApplication.AboutPanelOptionKey.applicationVersion: version,
        NSApplication.AboutPanelOptionKey.version: "Build \(build)",
        NSApplication.AboutPanelOptionKey.credits: credits,
        NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyrightLine,
    ])
}

extension Notification.Name {
    static let reloadRequested = Notification.Name("coderpad.reloadRequested")
    static let openPadByURLRequested = Notification.Name("coderpad.openPadByURLRequested")
    static let padUpdated = Notification.Name("coderpad.padUpdated")
    static let padDeleted = Notification.Name("coderpad.padDeleted")
    static let questionUpdated = Notification.Name("coderpad.questionUpdated")
    static let questionDeleted = Notification.Name("coderpad.questionDeleted")
    static let openSettingsRequested = Notification.Name("coderpad.openSettingsRequested")
    static let openPadInBrowserRequested = Notification.Name("coderpad.openPadInBrowserRequested")
}

/// A one-shot request for the Pads pane to apply when it next appears. Unlike a
/// transient notification, it survives until the destination view actually mounts
/// and consumes it — so "switch to Pads, then filter/search/create" works even
/// when PadsView isn't on screen at the moment the request is made.
struct PadsRequest: Equatable {
    var ownerEmail: String?
    var search: String?
    var startCreating = false
}

/// The Questions-pane equivalent of `PadsRequest`.
struct QuestionsRequest: Equatable {
    var search: String?
    var startCreating = false
}

/// Single source of truth for the visible section and any pending request queued
/// for a section's pane. Centralizing this removes the ordering hazard of posting
/// "switch section" and "apply filter" as two separate notifications: the target
/// pane may not be mounted yet when the second one fires, so it would be dropped.
/// Here the request is durable state the pane reads on appear.
@Observable
final class AppNavigation {
    static let shared = AppNavigation()
    private init() {}

    var section: AppSection = .pads

    /// Consumed and cleared by PadsView when it appears or this value changes.
    var padsRequest: PadsRequest?
    /// Consumed and cleared by QuestionsView when it appears or this value changes.
    var questionsRequest: QuestionsRequest?

    /// A question id whose detail pane should immediately create a pad and open it
    /// inline (the in-pane browser), matching the detail view's "New Pad" button.
    /// Set by the Questions list's context menu (after selecting that question) and
    /// consumed/cleared by QuestionDetailView when it appears or this value changes.
    var createPadForQuestionID: Int?

    /// A question id whose detail pane should immediately present its edit sheet.
    /// Set by the Questions list's context menu (after selecting that question) and
    /// consumed/cleared by QuestionDetailView, mirroring `createPadForQuestionID`.
    var editQuestionID: Int?

    /// A question id whose detail pane should immediately present its delete
    /// confirmation. Routed (rather than deleting inline) so the context menu and
    /// the detail view share the same confirmation step before the irreversible delete.
    var deleteQuestionID: Int?

    /// A pad id whose detail pane should immediately present its edit sheet. The
    /// pad counterpart to `editQuestionID`, set by the Pad menu command and
    /// consumed/cleared by `PadDetailView` when it appears or this value changes.
    var editPadID: String?

    /// A pad id whose detail pane should immediately present its "End Interview"
    /// confirmation. Routed (rather than ending inline) so the menu command and the
    /// detail view share the same confirmation step before the live session is ended.
    var endPadID: String?

    /// A pad id whose detail pane should immediately present its delete
    /// confirmation — the pad counterpart to `deleteQuestionID`, never deleting
    /// without that confirmation step.
    var deletePadID: String?

    /// A pad id requested by the "Open Pad by ID" App Intent. Durable state (rather
    /// than a transient notification) so the request survives a cold launch where the
    /// intent fires before any view is listening. Consumed/cleared by ContentView.
    var openPadID: String?

    /// Switch to a section with no pending request.
    func show(_ section: AppSection) {
        self.section = section
    }

    /// Switch to Pads and queue a request for the list to apply on appear.
    func showPads(_ request: PadsRequest = PadsRequest()) {
        section = .pads
        padsRequest = request
    }

    /// Switch to Questions and queue a request for the list to apply on appear.
    func showQuestions(_ request: QuestionsRequest = QuestionsRequest()) {
        section = .questions
        questionsRequest = request
    }

    /// Queue a pad id to open in the in-app browser, consumed by ContentView.
    func openPad(id: String) {
        openPadID = id
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Honor the "Hide Dock icon" preference from the moment the app launches.
        GeneralSettings.applyDockVisibility()
    }
}

@main
struct coderpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Drives the app-wide light/dark override; nil follows the system appearance.
    @AppStorage(GeneralSettings.Key.appearance) private var appearance: AppAppearance = .system

    var body: some Scene {
        WindowGroup("CoderPad", id: "main") {
            ContentView()
                // Width floor is owned by `MainSplit`, derived from the live column
                // minimums (and enforced via the sidebar's auto-collapse) rather
                // than a hardcoded number here.
                .frame(minHeight: 540)
                .preferredColorScheme(appearance.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1100, height: 720)
        .commands {
            appCommands
            FindCommands()
            ViewCommands()
            PadCommands()
            QuestionCommands()
            WindowCommands()
        }

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

        Settings {
            SettingsView()
                .preferredColorScheme(appearance.colorScheme)
        }

        MenuBarExtra {
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
            Button("New Question…") {
                AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open Pad by URL…") {
                NotificationCenter.default.post(name: .openPadByURLRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])
            Divider()
            Button("Reload") {
                NotificationCenter.default.post(name: .reloadRequested, object: nil)
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
        CommandMenu("Go") {
            Button("Pads") { post(.pads) }.keyboardShortcut("1", modifiers: [.command])
            Button("Questions") { post(.questions) }.keyboardShortcut("2", modifiers: [.command])
            Button("Organization") { post(.organization) }.keyboardShortcut("3", modifiers: [.command])
            Button("Quota") { post(.quota) }.keyboardShortcut("4", modifiers: [.command])
            Divider()
            Button("Next Section") { cycleSection(by: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Section") { cycleSection(by: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
            Link("Get API Key", destination: CoderPadLinks.apiSettings)
        }
    }

    private func post(_ section: AppSection) {
        AppNavigation.shared.show(section)
    }

    /// Moves the visible section forward (`+1`) or back (`-1`) through the fixed
    /// section order, wrapping at the ends. Backs the Go menu's Next/Previous items.
    private func cycleSection(by delta: Int) {
        let order: [AppSection] = [.pads, .questions, .organization, .quota]
        let current = AppNavigation.shared.section
        let index = order.firstIndex(of: current) ?? 0
        let count = order.count
        let next = order[((index + delta) % count + count) % count]
        AppNavigation.shared.show(next)
    }

    private func showAbout() { showAboutPanel() }
}

/// Wires ⌘F to the search field of whichever pane is on screen. The pane
/// publishes a `findAction`; here we surface it as a standard Find menu item in
/// the Edit menu, disabled in sections (like Quota) that have nothing to search.
struct FindCommands: Commands {
    @FocusedValue(\.findAction) private var findAction

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Find") { findAction?.perform() }
                .keyboardShortcut("f", modifiers: [.command])
                .disabled(findAction == nil)
        }
    }
}

/// Adds "Customize Toolbar…" to the View menu, matching Mail, Finder, and other
/// system apps. SwiftUI makes the section toolbars user-customizable (via
/// `.toolbar(id:)`) and offers customization through the toolbar's right-click
/// menu, but provides no menu command for it — so this bridges to AppKit's
/// `runCustomizationPalette(_:)` on the frontmost window's `NSToolbar`.
///
/// The item enables only while `canCustomizeToolbar` is published — i.e. a main
/// window is key. Settings and the Pad Browser don't have a customizable
/// `NSToolbar`, so it stays disabled there rather than presenting nothing.
/// Placed `after: .toolbar` so it sits just below "Show/Hide Toolbar", the same
/// spot system apps use.
struct ViewCommands: Commands {
    @FocusedValue(\.canCustomizeToolbar) private var canCustomizeToolbar

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Customize Toolbar…") {
                NSApp.keyWindow?.toolbar?.runCustomizationPalette(nil)
            }
            .disabled(canCustomizeToolbar != true)
        }
    }
}

/// Top-level "Pad" menu: every action for the pad selected in the frontmost
/// window (published as `focusedPad`). Open and copy act directly; Edit, End
/// Interview, and Delete route through `AppNavigation` so the mounted
/// `PadDetailView` runs them with its existing sheet and confirmations — the same
/// pattern the Questions side uses — rather than duplicating that machinery here.
///
/// Several shortcuts (⌘↩ primary action, ⌘E edit, ⇧⌘C copy id, ⌘⌫ delete) are
/// shared with the Question menu. Only one of `focusedPad`/`focusedQuestion` is
/// ever set — the visible section publishes one and the other reverts to nil — so
/// at any moment exactly one menu's item is enabled and the shortcut is
/// unambiguous, while the muscle memory carries across both sections.
struct PadCommands: Commands {
    @FocusedValue(\.focusedPad) private var pad
    @Environment(\.openWindow) private var openWindow

    /// Mirrors `PadDetailView.isEnded`, so "End Interview" disables once the pad
    /// is already ended instead of routing a no-op confirmation.
    private var isEnded: Bool {
        guard let pad else { return false }
        return pad.isEnded
    }

    var body: some Commands {
        CommandMenu("Pad") {
            Button("Open Pad in Browser") {
                guard let pad, let url = pad.webURL else { return }
                NotificationCenter.default.post(name: .openPadInBrowserRequested, object: url)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(pad == nil)

            Button("Open Pad in New Window") {
                guard let pad, let url = pad.webURL else { return }
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "pad-browser", value: url)
            }
            .keyboardShortcut(.return, modifiers: [.command, .option])
            .disabled(pad == nil)

            Divider()

            Button("Edit Pad…") {
                guard let pad else { return }
                AppNavigation.shared.editPadID = pad.id
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(pad == nil)

            Divider()

            Button("Copy Pad ID") {
                guard let pad else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pad.id, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(pad == nil)

            Button("Copy Pad URL") {
                guard let pad else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pad.url, forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(pad == nil)

            Button("Copy Pad Title") {
                guard let pad else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pad.title.isEmpty ? pad.id : pad.title, forType: .string)
            }
            .disabled(pad == nil)

            Divider()

            Button("End Interview…") {
                guard let pad else { return }
                AppNavigation.shared.endPadID = pad.id
            }
            .disabled(pad == nil || isEnded)

            Button("Delete Pad…") {
                guard let pad else { return }
                AppNavigation.shared.deletePadID = pad.id
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(pad == nil)
        }
    }
}

/// Top-level "Question" menu: the Questions-pane counterpart to `PadCommands`,
/// acting on the question selected in the frontmost window (`focusedQuestion`).
/// New Pad / Edit / Delete route through `AppNavigation` so the mounted
/// `QuestionDetailView` performs them with its existing sheets and delete
/// confirmation — the same path the Questions list's context menu uses.
///
/// `⌘↩` mirrors the Pad menu's primary action: with a pad selected it opens the
/// pad, with a question selected it creates a pad from that question — each the
/// headline action of the corresponding detail view. See `PadCommands` for why
/// sharing shortcuts across the two menus is unambiguous.
struct QuestionCommands: Commands {
    @FocusedValue(\.focusedQuestion) private var question

    var body: some Commands {
        CommandMenu("Question") {
            Button("New Pad from Question") {
                guard let question else { return }
                AppNavigation.shared.createPadForQuestionID = question.id
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(question == nil)

            Divider()

            Button("Edit Question…") {
                guard let question else { return }
                AppNavigation.shared.editQuestionID = question.id
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(question == nil)

            Divider()

            Button("Copy Question ID") {
                guard let question else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(question.id), forType: .string)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(question == nil)

            Button("Copy Question Title") {
                guard let question else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(question.displayTitle, forType: .string)
            }
            .disabled(question == nil)

            Divider()

            Button("Delete Question…") {
                guard let question else { return }
                AppNavigation.shared.deleteQuestionID = question.id
            }
            .keyboardShortcut(.delete, modifiers: [.command])
            .disabled(question == nil)
        }
    }
}

/// Adds an "Open Main Window" item to the Window menu so the main window can be
/// reopened after it's closed — the app keeps running with no windows (see
/// `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`).
struct WindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button("Open Main Window") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}
