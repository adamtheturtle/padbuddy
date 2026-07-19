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
    /// Which window value produced `fetched`, compared whole (account AND id):
    /// per-campaign session ids collide across accounts, so an id-only staleness
    /// check let a reused window keep showing another account's session (#727).
    @State private var fetchedFor: ScreenTestWindowID?
    @State private var loadFailed = false
    @State private var refreshError: String?
    @State private var fallbackAccountID: UUID?
    @State private var loadGeneration = 0

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
        // A legacy value (no account) restored before the accounts store finished
        // loading captured no fallback, leaving the window following whichever
        // account was selected later (#1863): capture the first account that
        // appears, making the owner sticky from then on, and fill the window in.
        .onChange(of: accounts.currentAccountID) { _, _ in
            guard value?.account == nil, fallbackAccountID == nil else { return }

            captureFallbackAccountIfNeeded()
            if fetched == nil { Task { await refresh() } }
        }
        .onChange(of: account?.id) { previous, current in
            guard StandaloneWindowAccountResolution.accountDisappeared(
                previous: previous, current: current
            ) else { return }

            loadGeneration += 1
            fetched = nil
            fetchedFor = nil
            refreshError = nil
            loadFailed = true
        }
        .onReloadRequest { await refresh() }
    }

    /// Fetch the session on appear and on reload, so transient failures can recover
    /// without closing the restored window.
    private func load() async {
        captureFallbackAccountIfNeeded()
        // Compare the whole value: session ids collide across accounts (#727).
        if fetched != nil, fetchedFor != value {
            fetched = nil
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

        loadGeneration += 1
        let generation = loadGeneration
        do {
            let test = try await client.getTest(id: value.id)
            guard generation == loadGeneration else { return }

            fetched = test
            fetchedFor = value
            loadFailed = false
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }

            if fetched == nil {
                loadFailed = true
            } else {
                refreshError = StandaloneWindowRefreshError.screenTest.message
            }
        }
    }
}
