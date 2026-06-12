//
//  MenuBarView.swift
//  coderpad
//

import SwiftUI
import AppKit

struct MenuBarLabel: View {
    @State private var monitor = PadActivityMonitor.shared

    var body: some View {
        Image(systemName: monitor.unseenChangedCount > 0
              ? "doc.text.magnifyingglass.badge"
              : "doc.text.magnifyingglass")
    }
}

struct MenuBarView: View {
    @State private var store = AccountsStore.shared
    @State private var monitor = PadActivityMonitor.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    @State private var pads: [Pad] = []
    @State private var questions: [Question] = []
    @State private var quota: Quota?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("menuBarTopN") private var topN: Int = 3
    @AppStorage("menuBarStartedOnly") private var startedOnly = false
    @Environment(\.openWindow) private var openWindow

    /// The settings Stepper bounds this to 0…30, but a corrupted/externally-edited
    /// defaults value could be negative, and `Array.prefix(_:)` traps on a negative
    /// count — so clamp at every read site.
    private var topCount: Int { max(0, topN) }

    var body: some View {
        if let account = store.currentAccount {
            if monitor.unseenChangedCount > 0 {
                Text("\(monitor.unseenChangedCount) updated")
                    .font(.caption).foregroundStyle(.orange)
                Button("Mark All as Seen") { monitor.markSeen() }
            }

            Button("New Pad…") {
                Task { await createPad(PadCreate(), account: account) }
            }
            .keyboardShortcut("n")
            .disabled(account.isMock == false && account.apiKey.isEmpty)
            // Load the menu's data here (a stable, always-present action) keyed on the
            // active account, rather than hanging it off an unrelated leaf button.
            .task(id: store.currentAccountID) { await load(account: account) }

            if !questions.isEmpty {
                Menu("New Pad from Question") {
                    let favoriteIDs = Set(favorites.favorites(account: store.currentAccountID))
                    ForEach(questionsForMenu(favoriteIDs: favoriteIDs).prefix(topCount)) { q in
                        Button {
                            Task { await createPad(.fromQuestion(q), account: account) }
                        } label: {
                            // Starred questions lead the list and carry the star so
                            // a frequently used question is the first one-click pad.
                            if favoriteIDs.contains(q.id) {
                                Label(q.title.isEmpty ? "#\(q.id)" : q.title, systemImage: "star.fill")
                            } else {
                                Text(q.title.isEmpty ? "#\(q.id)" : q.title)
                            }
                        }
                    }
                }
                .disabled(account.isMock == false && account.apiKey.isEmpty)
            }

            Button("Open Pad by URL…") {
                openMain()
                NotificationCenter.default.post(name: .openPadByURLRequested, object: nil)
            }

            Divider()

            Text("My Pads · \(account.name)")
                .font(.caption).foregroundStyle(.secondary)
            if let quotaSummary {
                Text(quotaSummary)
                    .font(.caption).foregroundStyle(.secondary)
            }

            if isLoading && pads.isEmpty {
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

            Menu("Go to") {
                Button("Pads") { go(.pads) }
                Button("Questions") { go(.questions) }
                Button("Organization") { go(.organization) }
                Button("Quota") { go(.quota) }
                Divider()
                Button("Settings…") {
                    openMain()
                    NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
                }
            }

            Button("Reload") {
                Task { await load(account: account) }
            }
            .keyboardShortcut("r")

            Button("Settings…") {
                openMain()
                NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            }
            .keyboardShortcut(",")

            if store.accounts.count > 1 {
                Menu("Switch Account") {
                    ForEach(store.accounts) { acct in
                        Button {
                            store.currentAccountID = acct.id
                        } label: {
                            if acct.id == store.currentAccountID {
                                Label(acct.name, systemImage: "checkmark")
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
                NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            }
            .keyboardShortcut("n")

            Divider()

            Menu("Help") {
                Link("CoderPad API Documentation", destination: CoderPadLinks.apiDocs)
                Link("Get API Key", destination: CoderPadLinks.apiSettings)
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
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private func load(account: Account) async {
        isLoading = true
        errorMessage = nil
        // Clear the previous account's data so switching accounts doesn't briefly show
        // the old account's pads/questions/quota until the new fetch lands.
        pads = []
        questions = []
        quota = nil
        defer { isLoading = false }
        let client = account.makeClient()
        do {
            async let padsTask = client.listPads()
            async let qsTask = client.listQuestions()
            async let quotaTask = client.quota()
            let fetched = try await padsTask
            pads = fetched.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            if let qs = try? await qsTask {
                questions = qs.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            }
            quota = try? await quotaTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
