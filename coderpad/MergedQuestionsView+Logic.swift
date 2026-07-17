//
//  MergedQuestionsView+Logic.swift
//  coderpad
//
//  Data, filtering, fan-out refresh, and per-account-routed favorites for the
//  combined "All Accounts" questions list.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

extension MergedQuestionsView {
    // MARK: - Combined + filtered data

    /// Every account's questions, tagged with their source account and arranged by
    /// the active sort. Memoized into `scopedCache`; read many times in one `body`
    /// (filter pass, chip options, counts, empty-state checks).
    var scoped: [MergedQuestionRow] {
        scopedCache.rows
    }

    /// Rebuild the memoized `scoped` rows when the underlying data or sort changes,
    /// rather than once per render: the tagged-array build, cross-account sort, and
    /// chip-option Sets only rerun when the merged questions actually change, not on
    /// every keystroke / selection / filter toggle (#366/#633). Reads only
    /// `questionsByAccount` so it never triggers a cache read.
    func refreshScoped() {
        let mergeable = accounts.mergeableAccounts
        let signature = scopedSignature(mergeable: mergeable)
        guard scopedCache.signature != signature else { return }

        scopedCache.signature = signature

        var rows: [MergedQuestionRow] = []
        for account in mergeable {
            for question in questionsByAccount[account.id] ?? [] {
                rows.append(MergedQuestionRow(account: account, item: question))
            }
        }
        scopedCache.rows = sort.sorted(rows, question: { $0.item }, tieBreaker: \.id)
        // Rebuild the chip-option lists in the same pass, sharing the input signature.
        scopedCache.availableLanguages = Array(Set(rows.compactMap { $0.item.language?.lowercased() })
            .filter { !$0.isEmpty }).sorted()
        scopedCache.availableOwners = Array(Set(rows.map(\.item.ownerEmail))
            .filter { !$0.isEmpty }).sorted()
    }

    /// A cheap hash of everything `scoped` (and the chip-option lists) depends on:
    /// per mergeable account, its id and every question. `Question` is `Hashable`, so
    /// any change to a displayed field invalidates the memo — the cached rows carry
    /// these values into both the filter pass and the list. O(n) hashing replaces the
    /// per-render array rebuild + two full Set passes.
    func scopedSignature(mergeable: [Account]) -> Int {
        var hasher = Hasher()
        hasher.combine(sort)
        for account in mergeable {
            hasher.combine(account.id)
            let questions = questionsByAccount[account.id] ?? []
            hasher.combine(questions.count)
            for question in questions {
                hasher.combine(question)
            }
        }
        return hasher.finalize()
    }

    /// The account-namespaced row id used for selection and `ForEach` identity.
    /// Per-org question ids collide across accounts, so the id alone isn't unique.
    static func rowID(account: UUID, question: Int) -> String {
        "\(account.uuidString):\(question)"
    }

    /// Filtered rows arranged by the active sort, matching `QuestionsView.sorted`.
    /// Memoized into `sortedCache` once per render by `refreshSorted()`.
    var sorted: [MergedQuestionRow] {
        sortedCache.rows
    }

    /// Rebuild the memoized filtered + sorted rows for one render. Folds the filter
    /// pass in here (rather than a separately-recomputed `filtered`) so the list,
    /// overlay, and count bar share a single pass.
    func refreshSorted() {
        // Precompute each account's favorites once per render, so both the favorites
        // *filter* and every row's `isFavorite` check are O(1) and don't rebuild the
        // array per row (#367). Stored on the cache so the row body and swipe actions
        // share this pass.
        let favoritesByAccount = Dictionary(uniqueKeysWithValues: accounts.mergeableAccounts.map {
            ($0.id, Set(favorites.favorites(account: $0.id)))
        })
        // Skip the filter+sort on selection-only body passes (mirrors #395). `scoped` is
        // itself memoized, so its signature stands in for the rows; favoritesByAccount is
        // in the key so toggling a favorite still re-runs.
        let key = SortedQuestionsCache.Key(
            scopedSignature: scopedCache.signature ?? 0,
            filterSignature: filterSignature,
            favoritesOnly: favoritesOnly,
            favoritesByAccount: favoritesByAccount
        )
        guard sortedCache.key != key else { return }

        sortedCache.key = key
        sortedCache.favoritesByAccount = favoritesByAccount
        let searchQuery = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = scoped.filter { row in
            let item = row.item
            return (accountFilter == nil || row.account.id == accountFilter)
                && (!mineOnly || isMine(row))
                && (!favoritesOnly || (favoritesByAccount[row.account.id]?.contains(item.id) ?? false))
                && (languageFilter == nil || (item.language ?? "").lowercased() == languageFilter)
                && (ownerFilter == nil || item.ownerEmail == ownerFilter)
                && (typeFilter == nil || item.interviewType.rawValue == typeFilter)
                && (draftFilter == nil
                    || (draftFilter == "draft" && item.isDraft == true)
                    || (draftFilter == "published" && item.isDraft != true))
                // Locale-aware case-insensitive matching (see PadListLogic.matches).
                && (searchQuery.isEmpty
                    || item.title.localizedCaseInsensitiveContains(searchQuery)
                    || item.ownerEmail.localizedCaseInsensitiveContains(searchQuery)
                    || (item.language ?? "").localizedCaseInsensitiveContains(searchQuery)
                    || (item.authorName ?? "").localizedCaseInsensitiveContains(searchQuery))
        }
        sortedCache.rows = filtered
    }

    func isMine(_ row: MergedQuestionRow) -> Bool {
        row.account.owns(row.item.ownerEmail)
    }

    func isFavorite(_ row: MergedQuestionRow) -> Bool {
        // Consult the per-render memo built by `refreshSorted()` — O(1), no per-call
        // array allocation (#367).
        sortedCache.favoritesByAccount[row.account.id]?.contains(row.item.id) ?? false
    }

    /// Whether any account has at least one starred question, gating the Favorites
    /// preset chip.
    var hasAnyFavorites: Bool {
        accounts.mergeableAccounts.contains { !favorites.favorites(account: $0.id).isEmpty }
    }

    /// The scoped row for a namespaced row id, used to resolve the List selection
    /// back to a specific account's question (not just the first id match).
    func row(forRowID rowID: String) -> MergedQuestionRow? {
        scoped.first { $0.id == rowID }
    }

    /// The row to select after the row with `rowID` is deleted: the next visible
    /// row, then the previous, mirroring `MergedPadsView.neighborSelection`, so
    /// deleting the open question keeps the detail pane populated. Returns a
    /// namespaced row id since selection is keyed by row, not bare question id.
    func neighborRowID(forDeletedRowID rowID: String) -> String? {
        let visible = sorted
        guard let index = visible.firstIndex(where: { $0.id == rowID }) else { return visible.first?.id }

        if visible.indices.contains(index + 1) { return visible[index + 1].id }
        if visible.indices.contains(index - 1) { return visible[index - 1].id }
        return nil
    }

    /// Bridge a List selection change to the `Question` binding and publish the
    /// row's source account so the detail pane routes to the right client. A nil id
    /// clears the selection; a non-nil id that doesn't resolve yet (e.g. a row
    /// inserted this render) is left untouched so it isn't transiently blanked.
    func selectRow(_ rowID: String?) {
        guard let rowID else {
            selection = nil
            router.selectedQuestionAccountID = nil
            return
        }
        guard let scopedRow = row(forRowID: rowID) else { return }

        selection = scopedRow.item
        router.selectedQuestionAccountID = scopedRow.account.id
    }

    /// Select a specific scoped row (from a context menu or a freshly inserted
    /// question), keeping the List selection, the `Question` binding, and the
    /// routed account in step.
    func select(_ scopedRow: MergedQuestionRow) {
        router.selectedQuestionAccountID = scopedRow.account.id
        selection = scopedRow.item
        selectedRowID = scopedRow.id
        // Also move the List's own selection (the highlight) to this row, so a
        // context-menu action on an unselected row doesn't leave the visible
        // highlight pointing at a different row than the action targets.
        selectedRowIDs = [scopedRow.id]
    }

    // MARK: - Options

    /// Chip-option lists, memoized alongside `scoped` and recomputed only when the
    /// merged questions change (#366) rather than rebuilt over every row on each access.
    var availableLanguages: [String] {
        scopedCache.availableLanguages
    }

    var availableOwners: [String] {
        scopedCache.availableOwners
    }

    var activeFilterCount: Int {
        [languageFilter, ownerFilter, typeFilter, draftFilter].compactMap(\.self).count
            + (accountFilter != nil ? 1 : 0)
            + (mineOnly ? 1 : 0)
            // Favorites narrows the list, so it counts as an active filter,
            // matching the result-count bar's label.
            + (favoritesOnly ? 1 : 0)
    }

    var filterSignature: String {
        FilterSignature.make([
            search.trimmingCharacters(in: .whitespacesAndNewlines),
            languageFilter,
            ownerFilter,
            typeFilter,
            draftFilter,
            accountFilter?.uuidString,
            mineOnly ? "mine" : nil
        ])
    }

    var accountKey: String {
        accounts.mergeableAccounts.map {
            FilterSignature.make([
                $0.id.uuidString,
                $0.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                $0.resolvedBaseURL.absoluteString
            ])
        }
        .joined(separator: ",")
    }

    // MARK: - Loading

    func seedFromCache() {
        for account in accounts.mergeableAccounts where questionsByAccount[account.id] == nil {
            questionsByAccount[account.id] = cache.get(account.id)
        }
        publishRoutes()
    }

    func hydrateFromCacheIfEmpty() {
        var changed = false
        for account in accounts.mergeableAccounts where questionsByAccount[account.id]?.isEmpty != false {
            let warm = cache.cached(account.id)
            guard !warm.isEmpty else { continue }

            questionsByAccount[account.id] = warm
            changed = true
        }
        if changed { publishRoutes() }
    }

    func reload() async {
        let mergeable = accounts.mergeableAccounts.filter { !$0.apiKey.isEmpty }
        guard !mergeable.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }
        // Build the clients on the main actor; each is Sendable, so the concurrent
        // children below can hold one without crossing isolation to build it.
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        await withTaskGroup(of: (UUID, [Question]?, String?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let questions = try await target.client.listQuestions(sort: "updated_at,desc")
                        return (target.id, questions, nil)
                    } catch {
                        return (target.id, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, questions, errorText) in group {
                if let questions {
                    questionsByAccount[id] = questions
                    accountErrors[id] = nil
                    cache.set(id, questions: questions)
                } else {
                    accountErrors[id] = errorText
                }
                publishRoutes()
                isLoading = false
            }
        }
        // Stamp the refresh time for the "Updated X ago" freshness cue (#619).
        lastRefreshed = Date()
        // Cold start with empty caches: the list first appears here, so this is the
        // earliest the saved selection can be resolved. Idempotent (guarded by
        // `didRestoreSelection`), so the per-refresh calls after this are no-ops.
        restoreSelectedRowIfNeeded()
    }

    func publishRoutes() {
        var routes: [Int: UUID] = [:]
        for account in accounts.mergeableAccounts {
            for question in questionsByAccount[account.id] ?? [] {
                routes[question.id] = account.id
            }
        }
        router.setQuestionRoutes(routes)
    }

    // MARK: - Mutations

    /// Apply an edited question to its account's list. `account` is the owning
    /// account from the notification; it disambiguates a per-org id collision. When
    /// absent, fall back to the (collision-prone) routing map as before.
    func applyUpdated(_ question: Question, account: UUID? = nil) {
        guard let accountID = account ?? router.questionAccountID[question.id],
              var questions = questionsByAccount[accountID],
              let index = questions.firstIndex(where: { $0.id == question.id }) else { return }

        questions[index] = question
        questionsByAccount[accountID] = questions
        // Question ids collide across accounts, so also require the edited
        // question to belong to the account whose question is currently routed
        // into the detail pane — otherwise account B's edit would silently
        // replace account A's open question.
        if selection?.id == question.id, accountID == router.selectedQuestionAccountID {
            selection = question
        }
    }

    /// Remove a deleted question. With a known `account`, only that account's copy
    /// is dropped, so a colliding id in another account is left intact; without it,
    /// every account holding the id is updated (the prior behavior).
    func removeQuestion(id: Int, account: UUID? = nil) {
        let targets = account.map { [$0] } ?? Array(questionsByAccount.keys)
        for accountID in targets where questionsByAccount[accountID]?.contains(where: { $0.id == id }) == true {
            questionsByAccount[accountID] = questionsByAccount[accountID]?.filter { $0.id != id }
        }
        publishRoutes()
    }

    func insert(_ question: Question, into account: Account) {
        var questions = questionsByAccount[account.id] ?? []
        questions.insert(question, at: 0)
        questionsByAccount[account.id] = questions
        cache.set(account.id, questions: questions)
        publishRoutes()
    }

    // MARK: - Actions

    func toggleFavorite(_ row: MergedQuestionRow) {
        favorites.toggle(row.item.id, title: row.item.displayTitle, account: row.account.id,
                         undoManager: undoManager)
        if favoritesOnly, !hasAnyFavorites { favoritesOnly = false }
    }
}
