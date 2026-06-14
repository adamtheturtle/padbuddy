//
//  MergedQuestionsView+Logic.swift
//  coderpad
//
//  Data, filtering, fan-out refresh, and per-account-routed favorites for the
//  combined "All Accounts" questions list.
//

import AppKit
import SwiftUI

extension MergedQuestionsView {
    // MARK: - Combined + filtered data

    /// Every account's questions, tagged with their source account. Memoized into
    /// `scopedCache` once per render by `refreshScoped()`; read many times in one
    /// `body` (chip options, counts, empty-state checks).
    var scoped: [AccountScoped<Question>] {
        scopedCache.rows
    }

    /// Rebuild the memoized `scoped` rows for one render. Reads only
    /// `questionsByAccount` so it never triggers a cache read.
    func refreshScoped() {
        var rows: [AccountScoped<Question>] = []
        for account in accounts.mergeableAccounts {
            for question in questionsByAccount[account.id] ?? [] {
                rows.append(AccountScoped(account: account, item: question,
                                          id: Self.rowID(account: account.id, question: question.id)))
            }
        }
        scopedCache.rows = rows
    }

    /// The account-namespaced row id used for selection and `ForEach` identity.
    /// Per-org question ids collide across accounts, so the id alone isn't unique.
    static func rowID(account: UUID, question: Int) -> String {
        "\(account.uuidString):\(question)"
    }

    /// Filtered rows arranged by the active sort, matching `QuestionsView.sorted`.
    /// Memoized into `sortedCache` once per render by `refreshSorted()`.
    var sorted: [AccountScoped<Question>] {
        sortedCache.rows
    }

    /// Rebuild the memoized filtered + sorted rows for one render. Folds the filter
    /// pass in here (rather than a separately-recomputed `filtered`) so the list,
    /// overlay, and count bar share a single pass.
    func refreshSorted() {
        // Precompute each account's favorites once when filtering by favorites, so
        // membership is O(1) per row instead of rebuilding the array per row.
        let favoritesByAccount: [UUID: Set<Int>] = favoritesOnly
            ? Dictionary(uniqueKeysWithValues: accounts.mergeableAccounts.map {
                ($0.id, Set(favorites.favorites(account: $0.id)))
            })
            : [:]
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
                && (search.isEmpty
                    || item.title.localizedCaseInsensitiveContains(search)
                    || item.ownerEmail.localizedCaseInsensitiveContains(search)
                    || (item.language ?? "").localizedCaseInsensitiveContains(search)
                    || (item.authorName ?? "").localizedCaseInsensitiveContains(search))
        }
        switch sort {
        case .titleAsc:
            sortedCache.rows = filtered.sorted {
                $0.item.displayTitle.localizedCaseInsensitiveCompare($1.item.displayTitle) == .orderedAscending
            }
        case .titleDesc:
            sortedCache.rows = filtered.sorted {
                $0.item.displayTitle.localizedCaseInsensitiveCompare($1.item.displayTitle) == .orderedDescending
            }
        case .lastUsedDesc:
            sortedCache.rows = filtered.sorted {
                ($0.item.updatedAt ?? .distantPast) > ($1.item.updatedAt ?? .distantPast)
            }
        case .lastUsedAsc:
            sortedCache.rows = filtered.sorted {
                ($0.item.updatedAt ?? .distantPast) < ($1.item.updatedAt ?? .distantPast)
            }
        case .usedDesc:
            sortedCache.rows = filtered.sorted {
                ($0.item.used ?? 0) > ($1.item.used ?? 0)
            }
        case .usedAsc:
            sortedCache.rows = filtered.sorted {
                ($0.item.used ?? 0) < ($1.item.used ?? 0)
            }
        }
    }

    func isMine(_ row: AccountScoped<Question>) -> Bool {
        row.item.ownerEmail.caseInsensitiveCompare(row.account.userEmail) == .orderedSame
    }

    func isFavorite(_ row: AccountScoped<Question>) -> Bool {
        favorites.favorites(account: row.account.id).contains(row.item.id)
    }

    /// Whether any account has at least one starred question, gating the Favorites
    /// preset chip.
    var hasAnyFavorites: Bool {
        accounts.mergeableAccounts.contains { !favorites.favorites(account: $0.id).isEmpty }
    }

    /// The scoped row for a namespaced row id, used to resolve the List selection
    /// back to a specific account's question (not just the first id match).
    func row(forRowID rowID: String) -> AccountScoped<Question>? {
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
    func select(_ scopedRow: AccountScoped<Question>) {
        router.selectedQuestionAccountID = scopedRow.account.id
        selection = scopedRow.item
        selectedRowID = scopedRow.id
    }

    // MARK: - Options

    var availableLanguages: [String] {
        Array(Set(scoped.compactMap { $0.item.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }

    var availableOwners: [String] {
        Array(Set(scoped.map(\.item.ownerEmail)).filter { !$0.isEmpty }).sorted()
    }

    var activeFilterCount: Int {
        [languageFilter, ownerFilter, typeFilter, draftFilter].compactMap(\.self).count
            + (accountFilter != nil ? 1 : 0)
            + (mineOnly ? 1 : 0)
            // Favorites narrows the list and is reset by `clearAllFilters`, so it
            // counts as an active filter — matching the result-count bar's label.
            + (favoritesOnly ? 1 : 0)
    }

    func clearAllFilters() {
        languageFilter = nil; ownerFilter = nil; typeFilter = nil; draftFilter = nil
        accountFilter = nil; mineOnly = false; favoritesOnly = false
    }

    var filterSignature: String {
        [search, languageFilter, ownerFilter, typeFilter, draftFilter,
         accountFilter?.uuidString, mineOnly ? "mine" : nil]
            .map { $0 ?? "·" }.joined(separator: "|")
    }

    var accountKey: String {
        accounts.mergeableAccounts.map { "\($0.id.uuidString):\($0.apiKey.isEmpty ? 0 : 1)" }
            .joined(separator: ",")
    }

    // MARK: - Loading

    func seedFromCache() {
        for account in accounts.mergeableAccounts where questionsByAccount[account.id] == nil {
            questionsByAccount[account.id] = cache.get(account.id)
        }
        publishRoutes()
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
        if selection?.id == question.id { selection = question }
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

    func toggleFavorite(_ row: AccountScoped<Question>) {
        favorites.toggle(row.item.id, account: row.account.id)
        if favoritesOnly, !hasAnyFavorites { favoritesOnly = false }
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
