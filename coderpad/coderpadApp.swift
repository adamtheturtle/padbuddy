//
//  coderpadApp.swift
//  coderpad
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let createPadRequested = Notification.Name("coderpad.createPadRequested")
    static let sectionRequested = Notification.Name("coderpad.sectionRequested")
    static let reloadRequested = Notification.Name("coderpad.reloadRequested")
    static let openPadByURLRequested = Notification.Name("coderpad.openPadByURLRequested")
    static let padUpdated = Notification.Name("coderpad.padUpdated")
    static let padsSearchRequested = Notification.Name("coderpad.padsSearchRequested")
    static let questionUpdated = Notification.Name("coderpad.questionUpdated")
    static let questionDeleted = Notification.Name("coderpad.questionDeleted")
    static let openPadIDRequested = Notification.Name("coderpad.openPadIDRequested")
    static let openSettingsRequested = Notification.Name("coderpad.openSettingsRequested")
    static let createQuestionRequested = Notification.Name("coderpad.createQuestionRequested")
    static let openPadInBrowserRequested = Notification.Name("coderpad.openPadInBrowserRequested")
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
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultLaunchBehavior(.presented)
        .commands {
            appCommands
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
                NotificationCenter.default.post(name: .createPadRequested, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])
            Button("New Question…") {
                NotificationCenter.default.post(name: .sectionRequested, object: AppSection.questions)
                NotificationCenter.default.post(name: .createQuestionRequested, object: nil)
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
        NotificationCenter.default.post(name: .sectionRequested, object: section)
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
        ])
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
