//
//  MergedQuestionsView+Loading.swift
//  coderpad
//
//  Cache seeding and the fan-out network refresh behind the combined
//  "All Accounts" questions list.
//

import SwiftUI

extension MergedQuestionsView {
    func seedFromCache() {
        var changed = false
        for account in accounts.mergeableAccounts where questionsByAccount[account.id] == nil {
            questionsByAccount[account.id] = cache.get(account.id)
            changed = true
        }
        if changed {
            questionsRevision += 1
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
        if changed {
            questionsRevision += 1
            publishRoutes()
        }
    }

    // swiftlint:disable:next function_body_length
    func reload(force: Bool = false) async {
        reportIneligibleAccounts()
        let mergeable = accounts.mergeableAccounts.filter(\.isInterviewFetchEligible)
        guard !mergeable.isEmpty else { return }

        // Claim the newest generation; an older overlapping reload stops applying
        // the moment a newer one starts, so its per-account results can't mix
        // stale rows into a fresher merged list (#1227), and a cancelled task
        // can't keep mutating state after navigation or an account change (#1229).
        reloadGeneration &+= 1
        let generation = reloadGeneration

        isLoading = true
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }
        let targets = mergeable.map { (id: $0.id, client: $0.makeClient()) }
        let clientsByID = Dictionary(targets.map { ($0.id, $0.client) }, uniquingKeysWith: { first, _ in first })
        let cacheLoads = beginCacheLoads(targets)
        accountErrors.merge(NavigationPrefetchHealth.snapshot(kind: .questions)) { current, _ in current }
        var fetchedByAccount: [UUID: [Question]] = [:]
        var fetchedErrors: [UUID: String] = [:]
        await withTaskGroup(of: (UUID, [Question]?, String?).self) { group in
            for target in targets {
                group.addTask {
                    do {
                        let questions = try await APIReadCoordinator.shared.questions(
                            accountID: target.id, client: target.client, force: force
                        )
                        return (target.id, questions, nil)
                    } catch {
                        return (target.id, nil, error.localizedDescription)
                    }
                }
            }
            for await (id, questions, errorText) in group {
                if let questions {
                    fetchedByAccount[id] = questions
                } else {
                    fetchedErrors[id] = errorText
                }
            }
        }
        guard generation == reloadGeneration, !Task.isCancelled else { return }

        // Apply every account's result together, mirroring MergedPadsView: applying
        // (and publishing routes) per-result inside the stream rendered whichever
        // accounts answered first, fluctuating filters/counts and letting a saved
        // selection resolve before its intended account arrived (#1228). Only
        // accounts still configured apply: one removed or re-keyed while its fetch
        // ran must not resurface in rows or errors (#1225); the cache setter
        // separately validates the fetching client's credentials.
        let mergeableIDs = Set(accounts.mergeableAccounts.map(\.id))
        for (id, questions) in fetchedByAccount where mergeableIDs.contains(id) {
            questionsByAccount[id] = questions
            accountErrors[id] = nil
            NavigationPrefetchHealth.clear(account: id, kind: .questions)
            if let client = clientsByID[id], let cacheLoad = cacheLoads[id] {
                cache.set(id, questions: questions, via: client, accepting: cacheLoad)
            }
        }
        for (id, errorText) in fetchedErrors where mergeableIDs.contains(id) {
            accountErrors[id] = errorText
        }
        // Prune rows and errors left by accounts that are gone, so a reintroduced
        // UUID can't inherit an old failure or stale list (#1230).
        questionsByAccount = questionsByAccount.filter { mergeableIDs.contains($0.key) }
        accountErrors = accountErrors.filter { mergeableIDs.contains($0.key) }
        questionsRevision += 1
        publishRoutes()
        // The defer above clears isLoading once EVERY account has answered; clearing
        // it per-result made the first fast account end the loading state while
        // slower accounts were still fetching (#728), unlike MergedPadsView.
        // Stamp the refresh time for internal refresh bookkeeping.
        lastRefreshed = Date()
        // Cold start with empty caches: the list first appears here, so this is the
        // earliest the saved selection can be resolved. Idempotent (guarded by
        // `didRestoreSelection`), so the per-refresh calls after this are no-ops.
        restoreSelectedRowIfNeeded(loadComplete: true)
    }

    private func beginCacheLoads(_ targets: [(id: UUID, client: CoderPadClient)]) -> [UUID: Int] {
        var loads: [UUID: Int] = [:]
        for target in targets {
            guard loads[target.id] == nil else { continue }

            if let token = cache.beginLoad(target.id, via: target.client) {
                loads[target.id] = token
            }
        }
        return loads
    }

    // The row mutations (edit/delete/create) and `publishRoutes` live in
    // MergedQuestionsView+Mutations.swift to keep this file under the length lint.

    // MARK: - Actions

    func toggleFavorite(_ row: MergedQuestionRow) {
        favorites.toggle(row.item.id, title: row.item.displayTitle, account: row.account.id,
                         undoManager: undoManager)
        if favoritesOnly, !hasAnyFavorites {
            favoritesOnly = false
        }
    }

    private func reportIneligibleAccounts() {
        for account in accounts.mergeableAccounts where !account.isInterviewFetchEligible {
            accountErrors[account.id] = account.interviewFetchUnavailableMessage
        }
    }
}
