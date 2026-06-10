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
            } else if pads.isEmpty {
                Text("No pads").foregroundStyle(.secondary)
            } else {
                ForEach(pads.prefix(topN)) { pad in
                    Button {
                        if let url = URL(string: pad.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text(padLabel(pad))
                    }
                }
                if pads.count > topN {
                    Text("…\(pads.count - topN) more").foregroundStyle(.secondary)
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

    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    private func load(account: Account) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let client = account.isMock ? CoderPadClient.mock() : CoderPadClient.live(apiKey: account.apiKey)
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
