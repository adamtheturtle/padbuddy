//
//  SpotlightIndexer+Gating.swift
//  coderpad
//
//  What decides whether queued index work is still allowed to write: the global
//  clear generation (#2420) and the per-account removal tombstones (#2419). Split
//  from SpotlightIndexer.swift to keep that file within its length limits.
//

import CoreSpotlight
import Foundation

extension SpotlightIndexer {
    @MainActor private static var seedTask: Task<Void, Never>?
    @MainActor private static var seedGeneration = 0

    /// Accounts torn down this session. An account re-added later clears its own
    /// tombstone when its first index pass runs — see `mayIndex(account:)`.
    /// Internal, not private: `removeAccount` in SpotlightIndexer.swift inserts into
    /// it inside the same lock it already holds.
    nonisolated(unsafe) static var removedAccounts: Set<UUID> = []

    /// Whether work queued at `generation` may still write for `account`.
    nonisolated static func mayIndex(generation: Int, account: UUID) -> Bool {
        guard mayIndex(generation: generation) else { return false }

        return enrichmentLock.withLock { !removedAccounts.contains(account) }
    }

    /// Marks an account indexable again, called when a fresh index pass begins for
    /// it: a re-added account must not stay blocked by its earlier removal.
    nonisolated static func reinstate(account: UUID) {
        enrichmentLock.withLock { _ = removedAccounts.remove(account) }
    }

    /// Bumped by every `clearAll()`. Index work captures the value it was queued
    /// under and abandons itself if a clear has happened since.
    ///
    /// Re-checking the preference at execution time (#734) covers a straightforward
    /// opt-out, but not a quick off-and-on again: by the time a queued write ran, the
    /// preference could be true once more, so items from before the clear were
    /// re-indexed into an index the user had just emptied (#2420).
    private nonisolated(unsafe) static var clearGeneration = 0

    /// The current clear generation, read under the same lock that writes it.
    nonisolated static func currentClearGeneration() -> Int {
        enrichmentLock.withLock { clearGeneration }
    }

    /// Whether work queued at `generation` may still write.
    nonisolated static func mayIndex(generation: Int) -> Bool {
        guard UserDefaults.standard.bool(forKey: GeneralSettings.Key.spotlightIndexing) else { return false }

        return enrichmentLock.withLock { generation == clearGeneration }
    }

    /// Clears everything this app indexed — used when the user turns the feature off.
    /// Seeds the index from every account's cached pads and questions, yielding
    /// between accounts.
    ///
    /// Both opt-in paths — the Settings toggle and a pulled preference — used to run
    /// this loop straight through on the main actor, so a large cache could stall
    /// Settings or app launch while the index updates were scheduled (#2156). Yielding
    /// lets the run loop breathe between accounts; the work itself still has to happen
    /// on the main actor, since the caches live there.
    static func seedFromCaches() {
        seedTask?.cancel()
        seedGeneration += 1
        let generation = seedGeneration
        seedTask = Task { @MainActor in
            defer {
                if generation == seedGeneration { seedTask = nil }
            }
            for account in AccountsStore.shared.accounts {
                guard !Task.isCancelled,
                      generation == seedGeneration,
                      GeneralSettings.spotlightIndexing else { return }

                updatePads(PadsCacheStore.shared.get(account.id), account: account.id)
                updateQuestions(QuestionsCacheStore.shared.get(account.id), account: account.id)
                await Task.yield()
            }
        }
    }

    static func clearAll() {
        seedGeneration += 1
        seedTask?.cancel()
        seedTask = nil
        // Stop any running enrichment before dropping the bookkeeping it relies on, so
        // turning indexing off takes effect immediately rather than after the current
        // batch of model calls drains (#2409).
        cancelEnrichment()
        enrichmentLock.withLock {
            clearGeneration += 1
            indexedPadIdentifiersByAccount.removeAll()
            indexedQuestionIdentifiersByAccount.removeAll()
            questionEnrichmentGenerations.removeAll()
            enrichedQuestionFingerprints.removeAll()
            indexedPadFingerprints.removeAll()
            indexedQuestionFingerprints.removeAll()
            UserDefaults.standard.removeObject(forKey: PersistenceKey.pads)
            UserDefaults.standard.removeObject(forKey: PersistenceKey.questions)
        }
        enqueueDelete(operation: "clear all items") { completion in
            CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: completion)
        }
    }
}
