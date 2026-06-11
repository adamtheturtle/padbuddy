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
    @State private var pads: [Pad] = []
    @State private var questions: [Question] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("menuBarTopN") private var topN: Int = 10
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let account = store.currentAccount {
            if monitor.unseenChangedCount > 0 {
                Text("\(monitor.unseenChangedCount) updated")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("My Pads · \(account.name)")
                .font(.caption).foregroundStyle(.secondary)

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

            if isLoading && pads.isEmpty {
                Text("Loading…").foregroundStyle(.secondary)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).lineLimit(2)
            } else if myPads.isEmpty {
                Text("No pads").foregroundStyle(.secondary)
            } else {
                ForEach(myPads.prefix(topN)) { pad in
                    Button {
                        if let url = URL(string: pad.url) {
                            BrowserSettings.openExternally(url)
                        }
                    } label: {
                        Text(padLabel(pad))
                    }
                }
                if myPads.count > topN {
                    Text("…\(myPads.count - topN) more").foregroundStyle(.secondary)
                }
            }

            if !questions.isEmpty {
                Divider()
                Menu("Recent Questions") {
                    ForEach(questions.prefix(topN)) { q in
                        Button {
                            openMain()
                        } label: {
                            Text(q.title.isEmpty ? "#\(q.id)" : q.title)
                        }
                    }
                }
            }

            Divider()

            Button("New Pad…") {
                Task { await createPad(PadCreate(), account: account) }
            }
            .keyboardShortcut("n")
            .disabled(account.isMock == false && account.apiKey.isEmpty)

            if !questions.isEmpty {
                Menu("New Pad from Question") {
                    ForEach(questions.prefix(topN)) { q in
                        Button {
                            Task { await createPad(.fromQuestion(q), account: account) }
                        } label: {
                            Text(q.title.isEmpty ? "#\(q.id)" : q.title)
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

            Button("Open CoderPad") {
                openMain()
            }
            .keyboardShortcut("o")

            Button("Reload") {
                Task { await load(account: account) }
            }
            .keyboardShortcut("r")

            Divider()

            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .task(id: account.id) { await load(account: account) }
        } else {
            Text("No account configured")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("Add Account…") {
                openMain()
                NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            }
            .keyboardShortcut("n")
            Button("Open CoderPad") { openMain() }
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    private func padLabel(_ pad: Pad) -> String {
        let title = pad.title.isEmpty ? pad.id : pad.title
        let language = (pad.language ?? "").isEmpty ? "" : " · \(pad.language!.languageDisplayName)"
        return "\(title)\(language)"
    }

    /// Pads owned by the account's configured email, if the user set one in Settings.
    /// Otherwise falls back to the most-frequent owner email in the fetched list, since
    /// the CoderPad API doesn't tell us which user the key belongs to.
    private var myPads: [Pad] {
        if let mine = store.currentAccount?.userEmail, !mine.isEmpty {
            return pads.filter { $0.ownerEmail == mine }
        }
        let owners = pads
            .map(\.ownerEmail)
            .filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        guard let mine = owners.max(by: { $0.value < $1.value })?.key else {
            return pads
        }
        return pads.filter { $0.ownerEmail == mine }
    }

    private func createPad(_ body: PadCreate, account: Account) async {
        let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey, baseURL: account.resolvedBaseURL)
        do {
            let pad = try await client.createPad(body)
            if let url = URL(string: pad.url) {
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
        defer { isLoading = false }
        let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey, baseURL: account.resolvedBaseURL)
        do {
            async let padsTask = client.listPads()
            async let qsTask = client.listQuestions()
            let fetched = try await padsTask
            pads = fetched.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            if let qs = try? await qsTask {
                questions = qs.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            }
            monitor.markSeen()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
