//
//  ContentView.swift
//  coderpad
//

import AppKit
import SwiftUI

enum AppSection: String, Hashable {
    case pads, questions, organization, quota
}

/// Strips the chrome Mail also omits: the window title (otherwise shown in the
/// title bar over the standard sidebar toggle) and the hairline separator under
/// the unified toolbar. The title bar itself stays standard so the system's own
/// sidebar toggle and View ▸ Show/Hide Sidebar command are present.
private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        ChromeView()
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        (nsView as? ChromeView)?.applyChrome()
    }

    /// Applies the chrome in `viewDidMoveToWindow`, when the window is guaranteed
    /// to exist — and again on every SwiftUI update, since toolbar changes can
    /// otherwise reinstate the separator.
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyChrome()
        }

        @objc func applyChrome() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
        }
    }
}

struct ContentView: View {
    @State private var store = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    @State private var addingAccount: Account?
    @State private var directory = OrgDirectory()
    @State private var monitor = AccountHealthMonitor.shared
    @State private var openPadURLDraft: String = ""
    @State private var showOpenPadURL = false
    @State private var showWhatsNew = false
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if store.currentAccount == nil {
                noAccountView
                    .frame(minWidth: 520, minHeight: 380)
            } else {
                MainSplit(
                    section: $nav.section,
                    directory: directory,
                    monitor: monitor
                )
            }
        }

        .background(WindowChromeConfigurator())
        .environment(\.orgDirectory, directory)
        .task {
            for await _ in AppRouter.openPadByURLRequests {
                showOpenPadURL = true
            }
        }
        // The "Open Pad by ID" intent routes through durable AppNavigation state so a
        // cold-launch request isn't dropped: consume whatever is already pending on
        // appear, and react to any value set afterwards.
        .task { consumeOpenPadID() }
        .onChange(of: nav.openPadID) { _, _ in consumeOpenPadID() }
        .task {
            for await _ in AppRouter.openSettingsRequests {
                openSettings()
            }
        }
        .task {
            for await url in AppRouter.openPadInBrowserRequests {
                openWindow(id: "pad-browser", value: url)
            }
        }
        .sheet(isPresented: $showOpenPadURL) {
            OpenPadURLSheet(
                urlString: $openPadURLDraft,
                onSubmit: { url in
                    openWindow(id: "pad-browser", value: url)
                    openPadURLDraft = ""
                    showOpenPadURL = false
                },
                onCancel: {
                    openPadURLDraft = ""
                    showOpenPadURL = false
                }
            )
        }
        // Mark the release seen on *any* dismissal (Continue, Esc, or closing the
        // window), so the sheet doesn't re-show every launch when dismissed without
        // the button. `onDismiss` is the single place this is recorded.
        .sheet(
            isPresented: $showWhatsNew,
            onDismiss: { WhatsNew.markSeen() },
            content: {
                WhatsNewSheet(release: WhatsNew.current, onDismiss: { showWhatsNew = false })
            }
        )
        .sheet(item: $addingAccount) { account in
            AccountEditor(initial: account) { saved in
                store.add(saved)
                addingAccount = nil
            } onCancel: {
                addingAccount = nil
            }
        }
        .task {
            if WhatsNew.shouldShow() { showWhatsNew = true }
        }
    }

    /// Opens any pad id queued by the "Open Pad by ID" intent, then clears it so it
    /// isn't reopened on the next change.
    private func consumeOpenPadID() {
        guard let id = nav.openPadID, !id.isEmpty else { return }
        nav.openPadID = nil
        if let url = URL(string: "https://app.coderpad.io/\(id)") {
            openWindow(id: "pad-browser", value: url)
        }
    }

    @ViewBuilder
    private var noAccountView: some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("Welcome to CoderPad", systemImage: "doc.text.magnifyingglass")
            } actions: {
                Button("Add Account") { addingAccount = Account(name: "", apiKey: "") }
                    .prominentGlassButtonStyle()
            }
        } else {
            ContentUnavailableView {
                Label("No account selected", systemImage: "person.crop.circle.badge.questionmark")
            } description: {
                Text("Choose one of your saved accounts in Settings.")
            } actions: {
                Button("Open Settings") { openSettings() }
                    .prominentGlassButtonStyle()
            }
        }
    }
}
