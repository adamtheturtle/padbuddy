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

    /// The owning account: the one named in the value, or the current account when the
    /// value omits it (single-account context).
    private var account: Account? {
        guard let value else { return nil }

        if let id = value.account { return accounts.accounts.first { $0.id == id } }
        return accounts.currentAccount
    }

    private var representedURL: URL? {
        guard let urlString = fetched?.url else { return nil }

        return URL(string: urlString)
    }

    var body: some View {
        Group {
            if let client = account?.makeScreenClient(), let test = fetched {
                let detail = ScreenTestDetailView(client: client, test: test)
                    .navigationTitle(test.candidateName ?? test.candidateEmail ?? String(localized: "Test Session"))
                // The recruiter dashboard URL backs the title-bar proxy icon (#609).
                if let urlString = test.url, let url = URL(string: urlString) {
                    detail.navigationDocument(url)
                } else {
                    detail
                }
            } else if value == nil || loadFailed || account?.makeScreenClient() == nil {
                // The system can restore this window without a value, the account may
                // have lost its Screen key, or the fetch can fail (e.g. the session was
                // deleted); show a placeholder rather than a blank window.
                ContentUnavailableView("Test Session Unavailable", systemImage: "person.crop.rectangle.stack",
                                       description: Text("This test session couldn’t be loaded."))
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .representedWindowURL(representedURL)
        .task(id: value) { await loadIfNeeded() }
    }

    /// Fetch the session once on appear (and whenever the window is reused for a
    /// different session), so a restored window fills in.
    private func loadIfNeeded() async {
        if let fetched, fetched.id != value?.id {
            self.fetched = nil
            loadFailed = false
        }
        guard fetched == nil, let value, let client = account?.makeScreenClient() else { return }

        do {
            fetched = try await client.getTest(id: value.id)
        } catch {
            loadFailed = true
        }
    }
}
