//
//  QuestionWindow.swift
//  coderpad
//
//  Hosts a question's detail in its own window, opened by double-clicking a
//  question row (#292). The window carries only an identifier so it can be
//  restored across launches; the heavyweight `Question` is resolved from the cache
//  (or fetched) on appear.
//

import SwiftUI

/// Identifies a question opened in its own window. Per-org question ids collide
/// across accounts, so the owning account travels with the id. `account` is `nil`
/// in a single-account context, where it resolves to the current account. Codable
/// and Hashable so it can back a `WindowGroup(for:)` and survive state restoration.
struct QuestionWindowID: Codable, Hashable {
    var account: UUID?
    var id: Int
}

/// Resolves a ``QuestionWindowID`` to its account and question and shows the same
/// `QuestionDetailView` the main window's detail column uses. The question comes
/// from the cache when present (the common case, since the window is opened from a
/// loaded row); otherwise it's fetched once, so a window restored on a cold cache
/// still fills in rather than showing an empty shell.
struct QuestionWindow: View {
    let value: QuestionWindowID?
    @State private var accounts = AccountsStore.shared
    @State private var cache = QuestionsCacheStore.shared
    @State private var fetched: Question?
    @State private var loadFailed = false
    @State private var refreshError: String?

    /// The owning account: the one named in the value, or the current account when
    /// the value omits it (single-account context).
    private var account: Account? {
        guard let value else { return nil }

        if let id = value.account { return accounts.accounts.first { $0.id == id } }
        return accounts.currentAccount
    }

    /// The question from the warm cache, if the owning account has it loaded.
    private var cachedQuestion: Question? {
        guard let value, let account else { return nil }

        return cache.cached(account.id).first { $0.id == value.id }
    }

    var body: some View {
        Group {
            if let account, let question = fetched ?? cachedQuestion {
                VStack(spacing: 0) {
                    if let refreshError {
                        StaleRefreshBanner(message: refreshError) {
                            Task { await refresh() }
                        }
                    }
                    QuestionDetailView(client: account.makeClient(),
                                       question: question,
                                       accountID: account.id)
                }
                .navigationTitle(question.displayTitle)
            } else if value == nil || loadFailed {
                // The system can restore this window without a value, or the fetch
                // can fail (e.g. the question was deleted); show a placeholder rather
                // than a blank window.
                ContentUnavailableView("Question Unavailable", systemImage: "questionmark.bubble",
                                       description: Text("This question couldn’t be loaded."))
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

    /// Fetch the question after first paint so restored windows don't treat
    /// persisted list snapshots as authoritative.
    private func load() async {
        // If the window was reused for a different question, drop the previous
        // fetch so its stale result can't satisfy the `fetched == nil` guard
        // (and can't render via `fetched ?? cachedQuestion`).
        if let fetched, fetched.id != value?.id {
            self.fetched = nil
            loadFailed = false
            refreshError = nil
        }
        await refresh()
    }

    private func refresh() async {
        guard let value, let account else { return }

        do {
            let question = try await account.makeClient().getQuestion(id: value.id)
            fetched = question
            loadFailed = false
            refreshError = nil
            AppRouter.questionUpdated(question, account: account.id)
        } catch is CancellationError {
            return
        } catch {
            if cachedQuestion == nil, fetched == nil {
                loadFailed = true
            } else {
                refreshError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
