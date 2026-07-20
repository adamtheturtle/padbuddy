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
        // the menu showing an initial fetch status so often: each open cleared its own
        // copy and waited on the network (#327). Now the menu shows cached data instantly and `load`
        // refreshes it in the background without clearing.
        // Internal, not private: `refreshLists` reads them from MenuBarView+Logic,
        // where it lives to keep this file within the length lint.
        @State var padsCache = PadsCacheStore.shared
        @State var questionsCache = QuestionsCacheStore.shared
        @State var isLoading = false
        @State var errorMessage: String?
        /// Accounts whose pad list has been verified by this menu session. Until a
        /// successful refresh, disk-backed active rows are explicitly marked cached
        /// rather than presented as confirmed-live interviews (#1494).
        @State var freshPadAccounts: Set<UUID> = []
        @State var creatingPadKeys: Set<String> = []
        /// Invalidates account-scoped create completions when the menu context changes.
        @State var transientGeneration = 0
        /// Monotonic id of the newest `loadMenu` call. Overlapping refreshes (the
        /// automatic `.task` plus a manual Reload) each capture their generation and
        /// only the newest may publish caches, `errorMessage`, or end `isLoading`, so
        /// an older, slower request can't overwrite a newer result (#775).
        @State var loadGeneration = 0
        /// Memo of the sorted pads/questions, refreshed at the top of `accountMenu` so
        /// the menu's several readers share one sort instead of re-sorting the full
        /// cached lists on every access (#370), and only when the caches or the
        /// accounts in view actually changed (#2112). Internal, not private: the
        /// ownership memo is read from MenuBarView+Logic.
        @State var listCache = MenuBarListCache()
        @AppStorage(SettingsPreferenceRecovery.menuBarTopNKey) private var topN: Int = 3
        @AppStorage("menuBarStartedOnly") var startedOnly = false
        @Environment(\.openSettings) var openSettings

        /// The settings Stepper bounds this to 0…30, but a corrupted/externally-edited
        /// defaults value could be negative, and `Array.prefix(_:)` traps on a negative
        /// count — so clamp at every read site.
        var topCount: Int {
            Self.normalizedTopCount(topN)
        }

        nonisolated static func normalizedTopCount(_ value: Int) -> Int {
            min(30, max(0, value))
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

        private var menuLoadKey: [MergedAccountToken] {
            let accounts = store.isMergedView
                ? store.mergeableAccounts
                : store.currentAccount.map { [$0] } ?? []
            return accounts.map(MergedAccountToken.init(account:))
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
            Group {
                if store.isMergedView {
                    // All Accounts shows no current account, so a bare "New Pad…"
                    // would silently create in the hidden previous selection (#776):
                    // name the destination with one item per account instead.
                    Menu("New Pad") {
                        newPadAccountWarning
                        ForEach(store.mergeableAccounts) { target in
                            let body = PadCreate()
                            Button("In \(target.name)…") {
                                Task { await createPad(body, account: target) }
                            }
                            .disabled(!Self.canCreatePad(account: target, isOffline: network.isOffline)
                                || isCreatingPad(body, account: target))
                        }
                    }
                } else {
                    let body = PadCreate()
                    Button("New Pad…") {
                        Task { await createPad(body, account: account) }
                    }
                    .keyboardShortcut("n")
                    .disabled(!Self.canCreatePad(account: account, isOffline: network.isOffline)
                        || isCreatingPad(body, account: account))
                }
            }
            // Load the menu's data here (a stable, always-present action) keyed on the
            // active account, rather than hanging it off an unrelated leaf button.
            .onChange(of: menuLoadKey) { _, _ in resetTransientState() }
            .task(id: menuLoadKey) { await loadMenu(activeAccount: account) }

            // Both New Pad and New Pad from Question create the pad under this account;
            // when the user has chosen the external browser, that browser may be signed
            // into a different CoderPad account, so warn first (#602).
            newPadAccountWarning

            if !questionRows.isEmpty {
                Menu("New Pad from Question") {
                    // The submenu is its own menu, so repeat the warning inside it.
                    newPadAccountWarning
                    // Built once for the whole submenu: the per-row check used to
                    // rebuild this account's favourites array and scan it (#2473).
                    let starred = favoriteQuestionIDs()
                    ForEach(questionsForMenu().prefix(topCount)) { row in
                        let body = PadCreate.fromQuestion(row.question)
                        Button {
                            Task { await createPad(from: row) }
                        } label: {
                            // Starred questions lead the list and carry the star so
                            // a frequently used question is the first one-click pad.
                            if starred[row.account.id]?.contains(row.question.id) == true {
                                Label(questionRowLabel(row), systemImage: "star.fill")
                            } else {
                                Text(questionRowLabel(row))
                            }
                        }
                        .disabled(!Self.canCreatePad(account: row.account, isOffline: network.isOffline)
                            || isCreatingPad(body, account: row.account))
                    }
                }
                .disabled(network.isOffline)
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
                Text("Fetching recent pads…").foregroundStyle(.secondary)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).lineLimit(2)
            } else if myPads.isEmpty {
                Text("No pads").foregroundStyle(.secondary)
            } else {
                ForEach(myPads.prefix(topCount)) { row in
                    padHandoffMenu(row, title: padRowLabel(row))
                }
                if myPads.count > topCount {
                    Text("…\(myPads.count - topCount) more").foregroundStyle(.secondary)
                }
            }
        }

        /// Makes the account boundary explicit before leaving the app. A browser may
        /// be authenticated to a different CoderPad organization, so every row offers
        /// both an external handoff and a safe URL-copy fallback (#1498).
        func padHandoffMenu(
            _ row: MenuBarPadRow,
            title: String,
            systemImage: String? = nil
        ) -> some View {
            let url = row.pad.webURL(fallbackBase: row.account.resolvedBaseURL)
            return Menu {
                Text("Account: \(row.account.name)")
                Text("Your browser may be signed in to another account.")
                    .foregroundStyle(.secondary)
                Divider()
                Button("Open in Browser") { openPadURL(url) }
                    .disabled(url == nil)
                Button("Copy Pad URL") {
                    if let url { Clipboard.copy(url.absoluteString) }
                }
                .disabled(url == nil)
            } label: {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
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

    /// Memo of the menu bar's sorted pads/questions. A plain reference type (not
    /// `@Observable`) so `accountMenu` can refresh it without mutating SwiftUI state
    /// mid-evaluation, mirroring the list views' filtered/sorted caches (#370).
    final class MenuBarListCache {
        /// What the rows were built from, so they rebuild when the caches or the
        /// accounts in view change rather than on every render (#2112).
        var signature: Int?
        var padRows: [MenuBarPadRow] = []
        var questionRows: [MenuBarQuestionRow] = []
        /// The ownership filter's result, memoized alongside the sorted rows.
        ///
        /// `myOwnedPads` was a plain computed property, and one menu render reads it
        /// several times — `myPads`, `activePads`, and a second filter inside the
        /// active-interview section — so the scan over every pad of every account ran
        /// two or three times per render (#2465).
        var myOwnedPads: [MenuBarPadRow] = []
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
