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

    var isValid: Bool {
        id > 0
    }
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
    /// Which window value produced `fetched`, compared whole (account AND id): ids
    /// collide across accounts, so an id-only staleness check let a reused window
    /// keep showing another account's data (#726).
    @State private var fetchedFor: QuestionWindowID?
    @State private var loadFailed = false
    @State private var refreshError: String?
    @State private var fallbackAccountID: UUID?
    /// Orders overlapping refreshes: each one claims the next generation and only
    /// publishes if its claim is still the newest. `refresh` captures `value` at call
    /// time, and cancellation is cooperative, so a fetch that ignores cancellation
    /// could otherwise land after the window was retargeted at another question and
    /// replace it (#2023).
    @State private var loadGeneration = 0

    /// The owning account: the one named in the value, or the current account captured
    /// when a legacy/restored value omits it. The fallback is intentionally sticky so
    /// switching accounts elsewhere cannot retarget this standalone window.
    private var account: Account? {
        guard let value else { return nil }

        let id = value.account ?? fallbackAccountID ?? accounts.currentAccountID
        return id.flatMap { id in accounts.accounts.first { $0.id == id } }
    }

    private var isExplicitAccountMissing: Bool {
        StandaloneWindowAccountResolution.isExplicitTargetMissing(value?.account, accounts: accounts.accounts)
    }

    /// The question from the warm cache, if the owning account has it loaded.
    ///
    /// Resolved when the window's value, account, or cache changes rather than in
    /// `body`: this scans the account's whole cached question list, and `body` reads it
    /// on every render for as long as `fetched` is nil (#2234, #2235).
    @State private var cachedQuestion: Question?

    private func resolveCachedQuestion() {
        guard let value, value.isValid, let account else {
            cachedQuestion = nil
            return
        }

        cachedQuestion = cache.cached(account.id).first { $0.id == value.id }
    }

    var body: some View {
        content
            .task(id: value, loadForCurrentValue)
            // The cache is warmed in the background, so the seed has to be re-resolved
            // when it lands — and when the owning account changes underneath the window.
            .onChange(of: cacheWriteGeneration, handleCacheWriteGenerationChange)
            .onChange(of: accounts.currentAccountID, handleCurrentAccountChange)
            .onChange(of: account?.id, handleAccountChange)
            .onReloadRequest { await refresh() }
    }

    private var content: some View {
        Group {
            if value?.isValid == true, let account, let question = fetched ?? cachedQuestion {
                loadedContent(account: account, question: question)
            } else if shouldShowUnavailableContent {
                unavailableContent
            } else {
                ProgressView().controlSize(.large)
            }
        }
    }

    private var shouldShowUnavailableContent: Bool {
        value?.isValid != true || isExplicitAccountMissing || loadFailed
    }

    private var cacheWriteGeneration: Int? {
        account.map { cache.writeGeneration[$0.id] ?? 0 }
    }

    private var unavailableContent: some View {
        // The system can restore this window without a value, or the fetch
        // can fail (e.g. the question was deleted); show a placeholder rather
        // than a blank window.
        ContentUnavailableView {
            Label("Question Unavailable", systemImage: "questionmark.bubble")
        } description: {
            Text("This question could not be loaded.")
        } actions: {
            if value?.isValid == true, !isExplicitAccountMissing {
                Button("Retry") {
                    Task { await refresh() }
                }
            }
        }
    }

    private func loadForCurrentValue() async {
        resolveCachedQuestion()
        await load()
    }

    private func handleCacheWriteGenerationChange(previous _: Int?, current _: Int?) {
        resolveCachedQuestion()
    }

    private func handleCurrentAccountChange(previous _: UUID?, current _: UUID?) {
        guard StandaloneWindowAccountResolution.shouldCaptureFallback(
            explicitTarget: value?.account,
            captured: fallbackAccountID,
            current: accounts.currentAccountID
        ) else { return }

        captureFallbackAccountIfNeeded()
        resolveCachedQuestion()
        if fetched == nil { Task { await refresh() } }
    }

    private func handleAccountChange(previous: UUID?, current: UUID?) {
        if StandaloneWindowAccountResolution.accountDisappeared(previous: previous, current: current) {
            resetForMissingAccount()
        } else {
            resolveCachedQuestion()
        }
    }

    private func loadedContent(account: Account, question: Question) -> some View {
        VStack(spacing: 0) {
            StandaloneAccountBanner(name: account.name)
            if let refreshError {
                StaleRefreshBanner(message: refreshError) { Task { await refresh() } }
            }
            QuestionDetailView(client: account.makeClient(), question: question, accountID: account.id)
        }
        .navigationTitle(question.displayTitle)
        .focusedSceneValue(\.focusedQuestion, question)
        .focusedSceneValue(\.focusedQuestionAccountID, account.id)
    }

    /// Fetch the question after first paint so restored windows don't treat
    /// persisted list snapshots as authoritative.
    private func load() async {
        captureFallbackAccountIfNeeded()
        // If the window was reused for a different question or a different account
        // (per-org ids collide across accounts), drop the previous fetch so its
        // stale result can't satisfy the `fetched == nil` guard (and can't render
        // via `fetched ?? cachedQuestion`) (#726).
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

    private func resetForMissingAccount() {
        loadGeneration += 1
        fetched = nil
        fetchedFor = nil
        cachedQuestion = nil
        refreshError = nil
        loadFailed = true
    }

    private func refresh() async {
        guard let value, value.isValid, let account else { return }

        loadGeneration += 1
        let generation = loadGeneration
        do {
            // The client is held rather than made inline, so the cache write below can
            // be checked against the credentials this response actually came from: a
            // re-key while the request was in flight must not land a pre-rekey response
            // in the new account's cache (#2623).
            let client = account.makeClient()
            let question = try await client.getQuestion(id: value.id)
            guard generation == loadGeneration else { return }

            fetched = question
            fetchedFor = value
            loadFailed = false
            refreshError = nil
            AppRouter.questionUpdated(question, account: account.id)
            // Warm the cache with the freshest copy even when no list is mounted to
            // receive the broadcast (a lone standalone window), so cache-backed
            // surfaces don't keep the stale row (#1005). No-op when unchanged.
            QuestionsCacheStore.shared.updateQuestion(question, account: account.id, via: client)
        } catch is CancellationError {
            return
        } catch {
            guard generation == loadGeneration else { return }

            if cachedQuestion == nil, fetched == nil {
                loadFailed = true
            } else {
                refreshError = StandaloneWindowRefreshError.question.message
            }
        }
    }
}
