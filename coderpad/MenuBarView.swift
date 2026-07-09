#if os(macOS)
//
//  MenuBarView.swift
//  coderpad
//

import AppKit
import SwiftUI

struct MenuBarLabel: View {
    var body: some View {
        Image(systemName: "doc.text.magnifyingglass")
            .accessibilityLabel("PadBuddy")
    }
}

struct MenuBarView: View {
    @State var store = AccountsStore.shared
    /// When offline the app is read-only, so the menu's create actions disable and a
    /// small note explains why (#321).
    @State private var network = NetworkMonitor.shared
    @State var favorites = FavoriteQuestionsStore.shared
    // Read the pads/questions from the same shared, disk-backed caches the main window
    // uses, rather than refetching into private state on every open. That's what kept
    // the menu showing "Loading…" so often: each open cleared its own copy and waited
    // on the network (#327). Now the menu shows cached data instantly and `load`
    // refreshes it in the background without clearing.
    @State private var padsCache = PadsCacheStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State var isLoading = false
    @State var errorMessage: String?
    /// Per-render memo of the sorted pads/questions, refreshed once at the top of
    /// `accountMenu` so the menu's several readers share one sort instead of
    /// re-sorting the full cached lists on every access (#370).
    @State private var listCache = MenuBarListCache()
    @AppStorage("menuBarTopN") private var topN: Int = 3
    @AppStorage("menuBarStartedOnly") var startedOnly = false
    @Environment(\.openSettings) var openSettings

    /// The settings Stepper bounds this to 0…30, but a corrupted/externally-edited
    /// defaults value could be negative, and `Array.prefix(_:)` traps on a negative
    /// count — so clamp at every read site.
    private var topCount: Int {
        max(0, topN)
    }

    /// Pads shown by the menu, tagged with their source account. In single-account
    /// mode this is just the current account; in merged mode it fans in every
    /// mergeable account so the menu matches the main window (#674).
    var padRows: [MenuBarPadRow] {
        listCache.padRows
    }

    /// Questions shown by the menu, tagged with their source account so "New Pad
    /// from Question" creates against the account that owns the question in merged
    /// mode (#674).
    var questionRows: [MenuBarQuestionRow] {
        listCache.questionRows
    }

    /// Sort cached pads/questions once per render into `listCache`. Mirrors the
    /// list views' memo pattern; called at the top of `accountMenu` before any
    /// reader touches menu data (#370/#674).
    private func refreshLists() {
        let accounts = store.isMergedView ? store.mergeableAccounts : store.currentAccount.map { [$0] } ?? []
        guard !accounts.isEmpty else {
            listCache.padRows = []
            listCache.questionRows = []
            return
        }

        let padRows = accounts.flatMap { account in
            padsCache.get(account.id).map { MenuBarPadRow(account: account, pad: $0) }
        }
        listCache.padRows = padRows.sorted { ($0.pad.updatedAt ?? .distantPast) > ($1.pad.updatedAt ?? .distantPast) }

        let questionRows = accounts.flatMap { account in
            questionsCache.get(account.id).map { MenuBarQuestionRow(account: account, question: $0) }
        }
        listCache.questionRows = questionRows
            .sorted { ($0.question.updatedAt ?? .distantPast) > ($1.question.updatedAt ?? .distantPast) }
    }

    private var menuLoadKey: String {
        if store.isMergedView {
            return "merged:" + store.mergeableAccounts.map(\.id.uuidString).joined(separator: ",")
        }
        return store.currentAccountID?.uuidString ?? "none"
    }

    var body: some View {
        if let account = store.currentAccount {
            accountMenu(account: account)
        } else {
            noAccountMenu
        }
    }

    /// The full menu shown when an account is active. Split into the helpers below
    /// so each view builder type-checks within the long-body diagnostic budget.
    private func accountMenu(account: Account) -> some View {
        // Refresh the per-render sort memo once, before any helper reads
        // `pads`/`questions` (#370).
        refreshLists()
        return Group {
            statusItems

            activeInterviewItems()

            newPadItems(account: account)

            Divider()

            myPadsItems(account: account)

            Divider()

            navigationItems(account: account)

            Divider()

            helpAndQuitItems
        }
    }

    /// A glanceable list of interviews that are live right now (#593), pinned near the
    /// top of the menu so an in-progress session is the first thing you see. Hidden
    /// entirely when nothing is active so the menu stays compact. Click-through opens
    /// the pad in the user's browser. Drawn from the same cached list as the rest of
    /// the menu, so it adds no network work.
    @ViewBuilder
    private func activeInterviewItems() -> some View {
        let live = activePads
        if !live.isEmpty {
            Text("Active Interviews")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(live.prefix(topCount)) { row in
                Button {
                    openPad(row.pad)
                } label: {
                    Label(padRowLabel(row), systemImage: "dot.radiowaves.left.and.right")
                }
            }
            if live.count > topCount {
                Text("…\(live.count - topCount) more").foregroundStyle(.secondary)
            }
            Divider()
        }
    }

    /// The offline banner shown at the top of the menu.
    @ViewBuilder
    private var statusItems: some View {
        if network.isOffline {
            Text("Offline (read-only)")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    /// New Pad and New Pad from Question. The New Pad button also hosts the menu's
    /// data load, keyed on the active account, as a stable always-present action.
    @ViewBuilder
    private func newPadItems(account: Account) -> some View {
        Button("New Pad…") {
            Task { await createPad(PadCreate(), account: account) }
        }
        .keyboardShortcut("n")
        .disabled((account.isMock == false && account.apiKey.isEmpty) || network.isOffline)
        // Load the menu's data here (a stable, always-present action) keyed on the
        // active account, rather than hanging it off an unrelated leaf button.
        .task(id: menuLoadKey) { await loadMenu(activeAccount: account) }

        // Both New Pad and New Pad from Question create the pad under this account;
        // when the user has chosen the external browser, that browser may be signed
        // into a different CoderPad account, so warn first (#602).
        newPadAccountWarning

        if !questionRows.isEmpty {
            Menu("New Pad from Question") {
                // The submenu is its own menu, so repeat the warning inside it.
                newPadAccountWarning
                ForEach(questionsForMenu().prefix(topCount)) { row in
                    Button {
                        Task { await createPad(.fromQuestion(row.question), account: row.account) }
                    } label: {
                        // Starred questions lead the list and carry the star so
                        // a frequently used question is the first one-click pad.
                        if favorites.favorites(account: row.account.id).contains(row.question.id) {
                            Label(questionRowLabel(row), systemImage: "star.fill")
                        } else {
                            Text(questionRowLabel(row))
                        }
                    }
                }
            }
            .disabled((account.isMock == false && account.apiKey.isEmpty) || network.isOffline)
        }
    }

    /// Caption note warning that a newly created pad opens in the default
    /// browser's signed-in CoderPad account, which may differ from this account.
    private var newPadAccountWarning: some View {
        Text("Opens in your browser's signed-in account")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// "My Pads" header and the user's recent pads (or a status line).
    @ViewBuilder
    private func myPadsItems(account: Account) -> some View {
        Text("My Pads · \(store.isMergedView ? "All Accounts" : account.name)")
            .font(.caption).foregroundStyle(.secondary)

        if isLoading, padRows.isEmpty {
            Text("Loading…").foregroundStyle(.secondary)
        } else if let errorMessage {
            Text(errorMessage).foregroundStyle(.red).lineLimit(2)
        } else if myPads.isEmpty {
            Text("No pads").foregroundStyle(.secondary)
        } else {
            ForEach(myPads.prefix(topCount)) { row in
                Button {
                    openPad(row.pad)
                } label: {
                    Text(padRowLabel(row))
                }
            }
            if myPads.count > topCount {
                Text("…\(myPads.count - topCount) more").foregroundStyle(.secondary)
            }
        }
    }

    /// Reload, settings, and account switching.
    @ViewBuilder
    private func navigationItems(account: Account) -> some View {
        Button("Reload") {
            Task { await loadMenu(activeAccount: account) }
        }
        .keyboardShortcut("r")

        Button("Settings…") {
            openSettingsPanel()
        }
        .keyboardShortcut(",")

        if store.accounts.count > 1 {
            Menu("Switch Account") {
                if store.mergeableAccounts.count >= 2 {
                    Button {
                        store.showAllAccounts = true
                    } label: {
                        if store.isMergedView {
                            Label("All Accounts", systemImage: "checkmark")
                        } else {
                            Text("All Accounts")
                        }
                    }
                    Divider()
                }
                ForEach(store.accounts) { acct in
                    Button {
                        store.showAllAccounts = false
                        store.currentAccountID = acct.id
                    } label: {
                        if !store.isMergedView, acct.id == store.currentAccountID {
                            Label(acct.name, systemImage: "checkmark")
                        } else if let symbol = acct.iconSymbol {
                            Label(acct.name, systemImage: symbol)
                        } else {
                            Text(acct.name)
                        }
                    }
                }
            }
        }
    }

    /// Help links, About, and Quit — shared by the configured and no-account menus.
    @ViewBuilder
    private var helpAndQuitItems: some View {
        Menu("Help") {
            Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
            Link("Get API Key", destination: CoderPadLinks.apiSettings)
            Divider()
            Link("Send Feedback…", destination: CoderPadLinks.feedbackMailto)
        }

        Button("About PadBuddy") { showAboutPanel() }

        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// The menu shown when no account is configured: a prompt to add one, plus the
    /// shared help and quit items.
    @ViewBuilder
    private var noAccountMenu: some View {
        Text("No account configured")
            .font(.caption).foregroundStyle(.secondary)
        Divider()
        Button("Add Account…") {
            // Jump straight into adding an account on the Accounts tab rather than
            // landing on a generic Settings tab (#452). The tab must be selected
            // *before* Settings opens — setting it from SettingsView.onAppear is too
            // late for the TabView to honor, which is why it stayed on General.
            SettingsNavigation.shared.selectedTab = .accounts
            SettingsNavigation.shared.startAddingAccount = true
            openSettingsPanel()
        }
        .keyboardShortcut("n")

        Divider()

        helpAndQuitItems
    }
}

/// Per-render memo of the menu bar's sorted pads/questions. A plain reference type
/// (not `@Observable`) so `accountMenu` can refresh it without mutating SwiftUI
/// state mid-evaluation, mirroring the list views' filtered/sorted caches (#370).
final class MenuBarListCache {
    var padRows: [MenuBarPadRow] = []
    var questionRows: [MenuBarQuestionRow] = []
}

struct MenuBarPadRow: Identifiable {
    let account: Account
    let pad: Pad

    var id: String {
        "\(account.id.uuidString):\(pad.id)"
    }
}

struct MenuBarQuestionRow: Identifiable {
    let account: Account
    let question: Question

    var id: String {
        "\(account.id.uuidString):\(question.id)"
    }
}
#endif
