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
                ? "CoderPad, \(monitor.unseenChangedCount) unseen pad \(monitor.unseenChangedCount == 1 ? "change" : "changes")"
                : "CoderPad")
    }
}

struct MenuBarView: View {
    @State private var store = AccountsStore.shared
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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("menuBarTopN") private var topN: Int = 3
    @AppStorage("menuBarStartedOnly") private var startedOnly = false
    @Environment(\.openWindow) private var openWindow

    /// The settings Stepper bounds this to 0…30, but a corrupted/externally-edited
    /// defaults value could be negative, and `Array.prefix(_:)` traps on a negative
    /// count — so clamp at every read site.
    private var topCount: Int {
        max(0, topN)
    }

    /// The current account's pads, newest first, from the shared cache. Empty until
    /// the account has ever loaded (cold cache), which is the only time the menu
    /// shows "Loading…".
    private var pads: [Pad] {
        guard let id = store.currentAccountID else { return [] }
        return padsCache.get(id).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// The current account's questions, newest first, from the shared cache.
    private var questions: [Question] {
        guard let id = store.currentAccountID else { return [] }
        return questionsCache.get(id).sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
    }

    /// The current account's cached quota, or `nil` before it has ever loaded.
    private var quota: Quota? {
        store.currentAccountID.flatMap { quotaCache.get($0) }
    }

    var body: some View {
        if let account = store.currentAccount {
            if network.isOffline {
                Text("Offline — read-only")
                    .font(.caption).foregroundStyle(.orange)
            }
            if monitor.unseenChangedCount > 0 {
                Text("\(monitor.unseenChangedCount) updated")
                    .font(.caption).foregroundStyle(.orange)
                Button("Mark All as Seen") { monitor.markSeen() }
            }

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

            Divider()

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

            Divider()

            // Section sub-menus mirroring the app's lists: the most recently
            // updated questions and pads, so the menu bar offers a quick jump into
            // recent work without opening the window first.
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

            Divider()

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

            Divider()

            Menu("Help") {
                Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
                Link("Get API Key", destination: CoderPadLinks.apiSettings)
                Divider()
                Link("Send Feedback…", destination: CoderPadLinks.feedbackMailto)
            }

            Button("About CoderPad") { showAboutPanel() }

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } else {
            Text("No account configured")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Add Account…") {
                openMain()
                AppRouter.requestOpenSettings()
            }
            .keyboardShortcut("n")

            Divider()

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
    }

    /// A one-line summary of the account's pad quota for the header, or `nil`
    /// when quota hasn't loaded yet (or the API doesn't report it).
    private var quotaSummary: String? {
        guard let quota else { return nil }
        if quota.unlimited == true { return "Unlimited pads" }
        if let remaining = quota.padsRemaining {
            if let limit = quota.billingCyclePadLimit {
                return "\(remaining) of \(limit) pads remaining"
            }
            return "\(remaining) pads remaining"
        }
        if let used = quota.padsUsed { return "\(used) pads used" }
        return nil
    }

    /// Opens the main window and switches it to `section`. The section is durable
    /// navigation state, so this works whether or not the window is already open.
    private func go(_ section: AppSection) {
        AppNavigation.shared.show(section)
        openMain()
    }

    private func padLabel(_ pad: Pad) -> String {
        let title = pad.title.isEmpty ? pad.id : pad.title
        let language = pad.language.flatMap { $0.isEmpty ? nil : " · \($0.languageDisplayName)" } ?? ""
        return "\(title)\(language)"
    }

    /// Label for a pad in the "Recent Activity" sub-menu, trailing the title with a
    /// relative "updated" time since recency is the point of that section.
    private func activityLabel(_ pad: Pad) -> String {
        let title = pad.title.isEmpty ? pad.id : pad.title
        guard let updated = pad.informativeUpdatedAt else { return title }
        return "\(title) · \(updated.formatted(.relative(presentation: .named)))"
    }

    /// Opens the main window on the Questions list with `question` selected, the
    /// same route the sidebar uses for a favorite question.
    private func openQuestion(_ question: Question) {
        AppNavigation.shared.showQuestions(QuestionsRequest(selectQuestionID: question.id))
        openMain()
    }

    /// Pads owned by the account's configured email, if the user set one in Settings.
    /// Otherwise falls back to the most-frequent owner email in the fetched list, since
    /// the CoderPad API doesn't tell us which user the key belongs to.
    private var myPads: [Pad] {
        let mineOnly: [Pad]
        if let mine = store.currentAccount?.userEmail, !mine.isEmpty {
            mineOnly = pads.filter { $0.ownerEmail == mine }
        } else {
            let owners = pads
                .map(\.ownerEmail)
                .filter { !$0.isEmpty }
                .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            if let mine = owners.max(by: { $0.value < $1.value })?.key {
                mineOnly = pads.filter { $0.ownerEmail == mine }
            } else {
                mineOnly = pads
            }
        }
        // Optionally narrow to active interviews when the user enables it in Settings.
        return startedOnly ? mineOnly.filter { $0.status == .active } : mineOnly
    }

    /// Questions for the "New Pad from Question" submenu, with favorites floated to
    /// the top (keeping the underlying most-recently-updated order within each
    /// group) so the user's starred questions lead the one-click pad list.
    private func questionsForMenu(favoriteIDs: Set<Int>) -> [Question] {
        guard !favoriteIDs.isEmpty else { return questions }
        return questions.filter { favoriteIDs.contains($0.id) }
            + questions.filter { !favoriteIDs.contains($0.id) }
    }

    private func createPad(_ body: PadCreate, account: Account) async {
        let client = account.makeClient()
        do {
            let pad = try await client.createPad(body)
            if let url = pad.webURL {
                BrowserSettings.openExternally(url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openMain() {
        AppActivator.bringToFront()
        openWindow(id: "main")
    }

    private func load(account: Account) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let client = account.makeClient()
        do {
            async let padsTask = client.listPads()
            async let qsTask = client.listQuestions()
            async let quotaTask = client.quota()
            // Write fetched results straight into the shared caches (no clearing
            // first): the menu — and every other view reading these stores — keeps
            // showing the previous data until the fresh data lands, so switching
            // accounts shows the new account's cache rather than a blank "Loading…".
            let fetched = try await padsTask
            PadsCacheStore.shared.set(account.id, pads: fetched)
            if let fetchedQuestions = try? await qsTask {
                QuestionsCacheStore.shared.set(account.id, questions: fetchedQuestions)
            }
            if let fetchedQuota = try? await quotaTask {
                QuotaCacheStore.shared.set(account.id, quota: fetchedQuota)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
