//
//  ScreenTestWindow.swift
//  coderpad
//
//  Hosts a Screen test session's detail (report) in its own window (#474) — the
//  Screen counterpart to opening a question in its own window (`QuestionWindow`).
//  The window carries only an identifier so it can be restored across launches; the
//  `ScreenClient` is rebuilt from the owning account and the session is fetched on
//  appear (there's no Screen test cache).
//

import SwiftUI

/// Identifies a Screen test session opened in its own window. Per-campaign session
/// ids are scoped to a Screen account, so the owning account travels with the id;
/// `account` is `nil` in a single-account context, where it resolves to the current
/// account. Codable and Hashable so it can back a `WindowGroup(for:)` and survive
/// state restoration.
struct ScreenTestWindowID: Codable, Hashable {
    var account: UUID?
    var id: Int
}

/// Resolves a ``ScreenTestWindowID`` to its account's Screen client, fetches the test
/// session, and shows the same `ScreenTestDetailView` the main window's detail column
/// uses. The session is always fetched (Screen sessions aren't cached), so a window
/// restored on a cold launch still fills in rather than showing an empty shell.
struct ScreenTestWindow: View {
    let value: ScreenTestWindowID?
    @State private var accounts = AccountsStore.shared
    @State private var fetched: ScreenTestSession?
    @State private var loadFailed = false
    @State private var refreshError: String?
    @State private var fallbackAccountID: UUID?

    /// The owning account: the one named in the value, or the current account captured
    /// when a legacy/restored value omits it. The fallback is intentionally sticky so
    /// switching accounts elsewhere cannot retarget this standalone window.
    private var account: Account? {
        guard let value else { return nil }

        let id = value.account ?? fallbackAccountID ?? accounts.currentAccountID
        return id.flatMap { id in accounts.accounts.first { $0.id == id } }
    }

    var body: some View {
        Group {
            if let client = account?.makeScreenClient(), let test = fetched {
                VStack(spacing: 0) {
                    if let refreshError {
                        StaleRefreshBanner(message: refreshError) {
                            Task { await refresh() }
                        }
                    }
                    ScreenTestDetailView(client: client, test: test)
                }
                .navigationTitle(test.candidateName ?? test.candidateEmail ?? String(localized: "Test Session"))
            } else if value == nil || loadFailed || account?.makeScreenClient() == nil {
                // The system can restore this window without a value, the account may
                // have lost its Screen key, or the fetch can fail (e.g. the session was
                // deleted); show a placeholder rather than a blank window.
                ContentUnavailableView {
                    Label("Test Session Unavailable", systemImage: "person.crop.rectangle.stack")
                } description: {
                    Text("This test session couldn’t be loaded.")
                } actions: {
                    if value != nil, account?.makeScreenClient() != nil {
                        Button("Retry") {
                            Task { await refresh() }
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .task(id: value) { await load() }
        .task {
            for await _ in AppRouter.reloads {
                await refresh()
            }
        }
    }

    /// Fetch the session on appear and on reload, so transient failures can recover
    /// without closing the restored window.
    private func load() async {
        captureFallbackAccountIfNeeded()
        if let fetched, fetched.id != value?.id {
            self.fetched = nil
            loadFailed = false
            refreshError = nil
        }
        await refresh()
    }

    private func captureFallbackAccountIfNeeded() {
        guard value?.account == nil, fallbackAccountID == nil else { return }

        fallbackAccountID = accounts.currentAccountID
    }

    private func refresh() async {
        guard let value, let client = account?.makeScreenClient() else { return }

        do {
            fetched = try await client.getTest(id: value.id)
            loadFailed = false
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            if fetched == nil {
                loadFailed = true
            } else {
                refreshError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
