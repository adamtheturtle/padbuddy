//
//  ContentView.swift
//  coderpad
//

import SwiftUI

enum AppSection: String, Hashable {
    case pads, questions, organization, quota, screen
}

extension AppSection {
    /// The top-to-bottom order of navigable top-level sections, computed from the
    /// shared account + quota stores. Single source of truth for both the sidebar's
    /// `sectionOrder` and the Go ▸ Next/Previous Section commands (`cycleSection`),
    /// so the two never disagree. Quota drops out on an unlimited single-account plan
    /// where its row is a non-navigable indicator (#306); Screen appears only when a
    /// Screen key is configured (#432/#442). Mirrors `quotaIsUnlimited` /
    /// `screenSectionAvailable` in ContentView+Sidebar.
    static var navigable: [AppSection] {
        let accounts = AccountsStore.shared
        let merged = accounts.isMergedView
        var order: [AppSection] = [.pads, .questions, .organization]

        let quotaUnlimited = !merged
            && (accounts.currentAccountID.map { QuotaCacheStore.shared.get($0)?.unlimited == true } ?? false)
        if !quotaUnlimited { order.append(.quota) }

        let screenAvailable = merged
            ? accounts.mergeableAccounts.contains { $0.makeScreenClient() != nil }
            : accounts.currentAccount?.makeScreenClient() != nil
        if screenAvailable { order.append(.screen) }

        return order
    }
}

struct ContentView: View {
    @State private var store = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    @State private var addingAccount: Account?
    @State private var directory = OrgDirectory()
    @State private var monitor = AccountHealthMonitor.shared
    @State private var network = NetworkMonitor.shared
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

        // Keep the title bar standard so the system's own sidebar toggle and
        // View ▸ Show/Hide Sidebar command are present, and let MainSplit's
        // `.navigationTitle`/`.navigationSubtitle` read out the current section
        // ("Pads", "Questions", "All accounts") like Mail's mailbox title. Only the
        // hairline separator under the unified toolbar is dropped, for the seamless
        // look — the title itself stays visible.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .environment(\.orgDirectory, directory)
        // While offline the whole window goes read-only: editing controls read this
        // to disable themselves, and the menu commands read the focused-scene mirror
        // below so they match (#321).
        .environment(\.isReadOnly, network.isOffline)
        .focusedSceneValue(\.isReadOnly, network.isOffline)
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
