//
//  MenuBarView.swift
//  coderpad
//

import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @State private var monitor = PadActivityMonitor.shared

    var body: some View {
        // `doc.text.magnifyingglass` has no `.badge` variant, so when there are
        // unseen pad changes we overlay a small dot rather than swap the glyph.
        // The menu bar renders the label as a monochrome template, so the dot
        // tracks the bar's foreground tint instead of showing red.
        Image(systemName: "doc.text.magnifyingglass")
            .overlay(alignment: .topTrailing) {
                if monitor.unseenChangedCount > 0 {
                    Circle()
                        .frame(width: 5, height: 5)
                        .offset(x: 3, y: -2)
                }
            }
            // The unseen-changes dot is shape- and tint-only, so name the count for
            // VoiceOver rather than leaving the menu bar item announcing a bare glyph (#79).
            .accessibilityLabel(monitor.unseenChangedCount > 0
                ? "CoderPad, \(monitor.unseenChangedCount) unseen pad "
                + "\(monitor.unseenChangedCount == 1 ? "change" : "changes")"
                : "CoderPad")
    }
}

struct MenuBarView: View {
    @State var store = AccountsStore.shared
    @State private var monitor = PadActivityMonitor.shared
    /// When offline the app is read-only, so the menu's create actions disable and a
    /// small note explains why (#321).
    @State private var network = NetworkMonitor.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    // Read the pads/questions/quota from the same shared, disk-backed caches the
    // main window uses, rather than refetching into private state on every open.
    // That's what kept the menu showing "Loading…" so often: each open cleared its
    // own copy and waited on the network (#327). Now the menu shows cached data
    // instantly and `load` refreshes it in the background without clearing.
    @State private var padsCache = PadsCacheStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State private var quotaCache = QuotaCacheStore.shared
    @State var isLoading = false
    @State var errorMessage: String?
    /// Per-render memo of the sorted pads/questions, refreshed once at the top of
    /// `accountMenu` so the menu's several readers share one sort instead of
    /// re-sorting the full cached lists on every access (#370).
    @State private var listCache = MenuBarListCache()
    @AppStorage("menuBarTopN") private var topN: Int = 3
    @AppStorage("menuBarStartedOnly") var startedOnly = false
    @Environment(\.openWindow) var openWindow

    /// The settings Stepper bounds this to 0…30, but a corrupted/externally-edited
    /// defaults value could be negative, and `Array.prefix(_:)` traps on a negative
    /// count — so clamp at every read site.
    private var topCount: Int {
        max(0, topN)
    }

    /// The current account's pads, newest first. Read from the per-render memo
    /// (`refreshLists()`), so the menu's several readers don't each re-sort the
    /// full cached list. Empty until the account has ever loaded (cold cache),
    /// which is the only time the menu shows "Loading…".
    var pads: [Pad] {
        listCache.pads
    }

    /// The current account's questions, newest first, from the per-render memo.
    var questions: [Question] {
        listCache.questions
    }

    /// Sort the current account's cached pads/questions once per render into
    /// `listCache`. Mirrors the list views' memo pattern; called at the top of
    /// `accountMenu` before any reader touches `pads`/`questions` (#370).
    private func refreshLists() {
        guard let id = store.currentAccountID else {
            listCache.pads = []
            listCache.questions = []
            return
        }

        listCache.pads = padsCache.get(id).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        listCache.questions = questionsCache.get(id)
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// The current account's cached quota, or `nil` before it has ever loaded.
    var quota: Quota? {
        store.currentAccountID.flatMap { quotaCache.get($0) }
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

            newPadItems(account: account)

            Divider()

            myPadsItems(account: account)

            Divider()

            recentMenus

            Divider()

            navigationItems(account: account)

            Divider()

            helpAndQuitItems
        }
    }

    /// Offline and unseen-change banners shown at the top of the menu.
    @ViewBuilder
    private var statusItems: some View {
        if network.isOffline {
            Text("Offline — read-only")
                .font(.caption).foregroundStyle(.orange)
        }
        if monitor.unseenChangedCount > 0 {
            Text("\(monitor.unseenChangedCount) updated")
                .font(.caption).foregroundStyle(.orange)
            Button("Mark All as Seen") { monitor.markSeen() }
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
        .task(id: store.currentAccountID) { await load(account: account) }

        if !questions.isEmpty {
            Menu("New Pad from Question") {
                let favoriteIDs = Set(favorites.favorites(account: store.currentAccountID))
                ForEach(questionsForMenu(favoriteIDs: favoriteIDs).prefix(topCount)) { question in
                    Button {
                        Task { await createPad(.fromQuestion(question), account: account) }
                    } label: {
                        // Starred questions lead the list and carry the star so
                        // a frequently used question is the first one-click pad.
                        if favoriteIDs.contains(question.id) {
                            Label(question.title.isEmpty ? "#\(question.id)" : question.title,
                                  systemImage: "star.fill")
                        } else {
                            Text(question.title.isEmpty ? "#\(question.id)" : question.title)
                        }
                    }
                }
            }
            .disabled((account.isMock == false && account.apiKey.isEmpty) || network.isOffline)
        }
    }

    /// "My Pads" header, quota summary, and the user's recent pads (or a status line).
    @ViewBuilder
    private func myPadsItems(account: Account) -> some View {
        Text("My Pads · \(account.name)")
            .font(.caption).foregroundStyle(.secondary)
        if let quotaSummary {
            Text(quotaSummary)
                .font(.caption).foregroundStyle(.secondary)
        }

        if isLoading, pads.isEmpty {
            Text("Loading…").foregroundStyle(.secondary)
        } else if let errorMessage {
            Text(errorMessage).foregroundStyle(.red).lineLimit(2)
        } else if myPads.isEmpty {
            Text("No pads").foregroundStyle(.secondary)
        } else {
            ForEach(myPads.prefix(topCount)) { pad in
                Button {
                    if let url = pad.webURL {
                        BrowserSettings.openExternally(url)
                    }
                } label: {
                    Text(padLabel(pad))
                }
            }
            if myPads.count > topCount {
                Text("…\(myPads.count - topCount) more").foregroundStyle(.secondary)
            }
        }
    }

    /// Section sub-menus mirroring the app's lists: the most recently updated
    /// questions and pads, so the menu bar offers a quick jump into recent work
    /// without opening the window first.
    @ViewBuilder
    private var recentMenus: some View {
        if !questions.isEmpty {
            Menu("Recent Questions") {
                ForEach(questions.prefix(topCount)) { question in
                    Button(question.displayTitle) { openQuestion(question) }
                }
            }
        }

        if !pads.isEmpty {
            Menu("Recent Activity") {
                ForEach(pads.prefix(topCount)) { pad in
                    Button(activityLabel(pad)) {
                        if let url = pad.webURL {
                            BrowserSettings.openExternally(url)
                        }
                    }
                }
            }
        }
    }

    /// Navigation into the main window's sections, plus reload, settings, and
    /// account switching.
    @ViewBuilder
    private func navigationItems(account: Account) -> some View {
        Menu("Go to") {
            Button("Pads") { go(.pads) }
            Button("Questions") { go(.questions) }
            Button("Organization") { go(.organization) }
            Button("Quota") { go(.quota) }
            Divider()
            Button("Settings…") {
                openMain()
                AppRouter.requestOpenSettings()
            }
        }

        Button("Reload") {
            Task { await load(account: account) }
        }
        .keyboardShortcut("r")

        Button("Settings…") {
            openMain()
            AppRouter.requestOpenSettings()
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

        Button("About CoderPad") { showAboutPanel() }

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
            openMain()
            AppRouter.requestOpenSettings()
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
    var pads: [Pad] = []
    var questions: [Question] = []
}
