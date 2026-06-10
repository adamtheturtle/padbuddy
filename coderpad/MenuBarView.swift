//
//  MenuBarView.swift
//  coderpad
//

import SwiftUI
import AppKit

struct MenuBarView: View {
    @State private var store = AccountsStore.shared
    @State private var pads: [Pad] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let account = store.currentAccount {
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
                ForEach(pads.prefix(10)) { pad in
                    Button {
                        if let url = URL(string: pad.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text(padLabel(pad))
                    }
                }
                if pads.count > 10 {
                    Text("…\(pads.count - 10) more").foregroundStyle(.secondary)
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
        let language = (pad.language ?? "").isEmpty ? "" : " · \(pad.language!)"
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
        do {
            let client = CoderPadClient(apiKey: account.apiKey)
            let fetched = try await client.listPads()
            pads = fetched.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
