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

    var scoped: [AccountScoped<Question>] {
        var rows: [AccountScoped<Question>] = []
        for account in accounts.mergeableAccounts {
            for question in questionsByAccount[account.id] ?? [] {
                rows.append(AccountScoped(account: account, item: question, id: String(question.id)))
            }
        }
        return rows
    }

    var filtered: [AccountScoped<Question>] {
        let lowered = search.lowercased()
        return scoped.filter { row in
            let item = row.item
            return (accountFilter == nil || row.account.id == accountFilter)
                && (!mineOnly || isMine(row))
                && (!favoritesOnly || isFavorite(row))
                && (languageFilter == nil || (item.language ?? "").lowercased() == languageFilter)
                && (ownerFilter == nil || item.ownerEmail == ownerFilter)
                && (typeFilter == nil || item.interviewType.rawValue == typeFilter)
                && (draftFilter == nil
                    || (draftFilter == "draft" && item.isDraft == true)
                    || (draftFilter == "published" && item.isDraft != true))
                && (lowered.isEmpty
                    || item.title.lowercased().contains(lowered)
                    || item.ownerEmail.lowercased().contains(lowered)
                    || (item.language ?? "").lowercased().contains(lowered)
                    || (item.authorName ?? "").lowercased().contains(lowered))
        }
    }

    /// Filtered rows arranged by the active sort, matching `QuestionsView.sorted`.
    var sorted: [AccountScoped<Question>] {
        let items = filtered
        switch sort {
        case .titleAsc:
            return items.sorted {
                $0.item.displayTitle.localizedCaseInsensitiveCompare($1.item.displayTitle) == .orderedAscending
            }
        case .titleDesc:
            return items.sorted {
                $0.item.displayTitle.localizedCaseInsensitiveCompare($1.item.displayTitle) == .orderedDescending
            }
        case .lastUsedDesc:
            return items.sorted { ($0.item.updatedAt ?? .distantPast) > ($1.item.updatedAt ?? .distantPast) }
        case .lastUsedAsc:
            return items.sorted { ($0.item.updatedAt ?? .distantPast) < ($1.item.updatedAt ?? .distantPast) }
        }
    }

    func isMine(_ row: AccountScoped<Question>) -> Bool {
        let email = row.account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return false }
        return row.item.ownerEmail.caseInsensitiveCompare(email) == .orderedSame
    }

    func isFavorite(_ row: AccountScoped<Question>) -> Bool {
        favorites.favorites(account: row.account.id).contains(row.item.id)
    }

    /// Whether any account has at least one starred question, gating the Favorites
    /// preset chip.
    var hasAnyFavorites: Bool {
        accounts.mergeableAccounts.contains { !favorites.favorites(account: $0.id).isEmpty }
    }

    func question(forID id: Int) -> Question? {
        for questions in questionsByAccount.values {
            if let match = questions.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    /// The question to select after the question with `id` is deleted: the next
    /// visible row, then the previous, mirroring `MergedPadsView.neighborSelection`,
    /// so deleting the open question keeps the detail pane populated.
    func neighborSelection(forDeletedQuestion id: Int) -> Question? {
        let visible = sorted.map(\.item)
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.first }
        if visible.indices.contains(index + 1) { return visible[index + 1] }
        if visible.indices.contains(index - 1) { return visible[index - 1] }
        return nil
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

    func applyUpdated(_ question: Question) {
        guard let accountID = router.questionAccountID[question.id],
              var questions = questionsByAccount[accountID],
              let index = questions.firstIndex(where: { $0.id == question.id }) else { return }
        questions[index] = question
        questionsByAccount[accountID] = questions
        if selection?.id == question.id { selection = question }
    }

    func removeQuestion(id: Int) {
        for (accountID, questions) in questionsByAccount where questions.contains(where: { $0.id == id }) {
            questionsByAccount[accountID] = questions.filter { $0.id != id }
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
