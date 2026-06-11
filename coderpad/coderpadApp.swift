//
//  coderpadApp.swift
//  coderpad
//

import SwiftUI
import AppKit

let copyrightLine = "Copyright © 2026 Adam Dangoor"

extension Notification.Name {
    static let reloadRequested = Notification.Name("coderpad.reloadRequested")
    static let openPadByURLRequested = Notification.Name("coderpad.openPadByURLRequested")
    static let padUpdated = Notification.Name("coderpad.padUpdated")
    static let padDeleted = Notification.Name("coderpad.padDeleted")
    static let questionUpdated = Notification.Name("coderpad.questionUpdated")
    static let questionDeleted = Notification.Name("coderpad.questionDeleted")
    static let openPadIDRequested = Notification.Name("coderpad.openPadIDRequested")
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
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

@main
struct coderpadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("CoderPad", id: "main") {
            ContentView()
                .frame(minWidth: 940, minHeight: 540)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 1100, height: 720)
        .commands {
            appCommands
            FindCommands()
            PadCommands()
        }

        WindowGroup("Pad Browser", id: "pad-browser", for: URL.self) { $url in
            if let url {
                PadBrowserView(url: url)
                    .navigationTitle(url.host ?? "Pad")
            }
        }

        Settings {
            SettingsView()
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
        CommandGroup(after: .newItem) {
            Button("New Pad…") {
                AppNavigation.shared.showPads(PadsRequest(startCreating: true))
            }
            .keyboardShortcut("n", modifiers: [.command])
            Button("New Question…") {
                AppNavigation.shared.showQuestions(QuestionsRequest(startCreating: true))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Pad by URL…") {
                NotificationCenter.default.post(name: .openPadByURLRequested, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])
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
        }
        CommandGroup(replacing: .help) {
            Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
            Link("Get API Key", destination: CoderPadLinks.apiSettings)
            Divider()
            Link("Source (GitHub)", destination: CoderPadLinks.sourceRepo)
        }
    }

    private func post(_ section: AppSection) {
        AppNavigation.shared.show(section)
    }

    private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let credits = NSAttributedString(
            string: """
A macOS client for the CoderPad Interview API.

Browse pads, questions, organization stats, and quota.
Multi-account, Keychain-backed, with a mock-data demo mode.

github.com/adamtheturtle/coderpad-macos
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

struct PadCommands: Commands {
    @FocusedValue(\.focusedPad) private var pad

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
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

            Button("Open Pad in Browser") {
                guard let pad, let url = URL(string: pad.url) else { return }
                NotificationCenter.default.post(name: .openPadInBrowserRequested, object: url)
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(pad == nil)
        }
    }
}
