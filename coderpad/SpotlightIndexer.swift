//
//  SpotlightIndexer.swift
//  coderpad
//

@preconcurrency import CoreSpotlight
import Foundation
import os.log
import UniformTypeIdentifiers

/// Optionally mirrors the user's pads and questions into the on-device Spotlight
/// index so they're findable system-wide. **Opt-in** (off by default, gated on
/// `GeneralSettings.spotlightIndexing`) because pad titles can carry candidate
/// names — the index is local to the device and nothing is uploaded, but the
/// titles do become visible to system search, so it's the user's choice.
///
/// Items are keyed `pad:<id>` / `question:<id>` and grouped under a per-account
/// domain so an account's items can be removed wholesale. Tapping a result
/// reopens the app via the handler in `coderpadApp` (see `onContinueUserActivity`).
enum SpotlightIndexer {
    private nonisolated static let logger = Logger(subsystem: "com.coderpad.app", category: "spotlight")
    // Internal (not private) so the parsing helpers in
    // SpotlightIndexer+Identifiers.swift can share them.
    nonisolated static let padPrefix = "pad:"
    nonisolated static let questionPrefix = "question:"
    private typealias SpotlightFinish = @Sendable () -> Void
    typealias SpotlightErrorCompletion = @Sendable ((any Error)?) -> Void
    private typealias SpotlightOperation = @Sendable (@escaping SpotlightFinish) -> Void

    private nonisolated static let operationQueue = DispatchQueue(label: "com.coderpad.app.spotlight.operations")
    // Internal (not private): the single-item removal + persistence halves in
    // SpotlightIndexer+Removals.swift mutate these under the same lock.
    nonisolated static let enrichmentLock = NSLock()
    nonisolated(unsafe) static var questionEnrichmentGenerations: [String: Int] = [:]
    /// Monotonic source for enrichment generations, so a value is never reused
    /// after its map entry is cleaned up on completion (#1727).
    nonisolated(unsafe) static var enrichmentGenerationCounter = 0
    /// Fingerprints (title + language + description) of questions already
    /// enriched, recorded when the model pass is *scheduled*: repeated refreshes
    /// of unchanged questions no longer restart model work (#1725), and the
    /// enrichment cap counts only questions still needing work, so a large org's
    /// tail is reached across passes instead of starving forever (#1724). Pruned
    /// alongside the identifier bookkeeping.
    nonisolated(unsafe) static var enrichedQuestionFingerprints: [String: Int] = [:]
    /// Seeded from UserDefaults so reconciliation spans launches: an item deleted
    /// server-side while the app was closed must still be detected as stale on the
    /// first refresh after relaunch, or it lingers in system search forever (#733).
    nonisolated(unsafe) static var indexedPadIdentifiersByAccount: [UUID: Set<String>] =
        loadPersistedIdentifiers(key: PersistenceKey.pads)
    nonisolated(unsafe) static var indexedQuestionIdentifiersByAccount: [UUID: Set<String>] =
        loadPersistedIdentifiers(key: PersistenceKey.questions)
    /// Whether persisted bookkeeping has been checked against the configured
    /// accounts this launch (#1734).
    @MainActor private static var didPruneOrphanedAccounts = false

    /// UserDefaults keys mirroring the in-memory indexed-identifier bookkeeping.
    /// Only populated while the user has Spotlight indexing enabled; `clearAll()`
    /// wipes them along with the index.
    nonisolated enum PersistenceKey {
        static let pads = "spotlight.indexedPadIdentifiers"
        static let questions = "spotlight.indexedQuestionIdentifiers"
    }

    /// How many questions one indexing pass will enrich with on-device keywords.
    /// Each enrichment runs the language model, so a big org's full list would be
    /// far too costly to summarize in one go; the cap keeps it bounded and the
    /// dropped remainder is logged rather than silently skipped.
    static let maxKeywordEnrichments = 50

    nonisolated static func domain(_ account: UUID) -> String {
        account.uuidString
    }

    /// A question's Spotlight identifier. Question ids are numbered *per org* and
    /// collide across accounts, while `uniqueIdentifier` is a global key — so it's
    /// namespaced with the account UUID (`question:<uuid>:<id>`). Without this,
    /// indexing one account's question overwrites another's same-id entry, and a
    /// single-account delete removes the other account's item too (#378). (Pads use
    /// global slug ids, so they need no such namespacing.)
    nonisolated static func questionIdentifier(id: Int, account: UUID) -> String {
        "\(questionPrefix)\(account.uuidString):\(id)"
    }

    /// A presentable Spotlight title: trimmed, with whitespace-only values
    /// treated as absent so results never show blank labels (#1728).
    nonisolated static func presentableTitle(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Indexes (or re-indexes) the account's pads. No-op unless the user enabled it.
    static func updatePads(_ pads: [Pad], account: UUID) {
        guard GeneralSettings.spotlightIndexing else { return }

        pruneOrphanedAccountsOnce()
        let identifiers = Set(pads.map { padIdentifier(id: $0.id, account: account) })
        reconcilePadIdentifiers(identifiers, account: account)

        // The description names the pad's state only: owner emails are identity
        // data the opt-in copy never mentioned, and they don't belong in system
        // search (#1736). Records are reduced to the three strings each item
        // needs on the main actor (`status.label` is main-actor presentation);
        // the heavy CSSearchableItem construction happens per chunk (#1729).
        let records = pads.map { pad in
            PadIndexRecord(
                identifier: padIdentifier(id: pad.id, account: account),
                title: presentableTitle(pad.title, fallback: pad.id),
                description: pad.status.label
            )
        }
        indexChunked(records) { record in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = record.title
            attrs.contentDescription = record.description
            return CSSearchableItem(uniqueIdentifier: record.identifier,
                                    domainIdentifier: domain(account),
                                    attributeSet: attrs)
        }
    }

    /// The strings one pad's Spotlight item needs, captured on the main actor so
    /// the chunked item construction can run off it (#1729).
    private nonisolated struct PadIndexRecord {
        let identifier: String
        let title: String
        let description: String
    }

    /// Indexes (or re-indexes) the account's questions. No-op unless enabled.
    static func updateQuestions(_ questions: [Question], account: UUID) {
        guard GeneralSettings.spotlightIndexing else { return }

        pruneOrphanedAccountsOnce()
        let identifiers = Set(questions.map { questionIdentifier(id: $0.id, account: account) })
        reconcileQuestionIdentifiers(identifiers, account: account)

        // Language only: author names are identity data the opt-in copy never
        // mentioned (#1736).
        indexChunked(questions) { question in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = presentableTitle(question.title, fallback: "#\(question.id)")
            attrs.contentDescription = question.language ?? ""
            return CSSearchableItem(uniqueIdentifier: questionIdentifier(id: question.id, account: account),
                                    domainIdentifier: domain(account),
                                    attributeSet: attrs)
        }
        enrichQuestionKeywords(questions, account: account)
    }

    /// Drops persisted bookkeeping (and index domains) for accounts that no
    /// longer exist — a removal that bypassed the normal teardown path would
    /// otherwise keep its identifiers in memory forever and skew reconciliation
    /// scans (#1734). Once per launch, from the MainActor entry points.
    @MainActor
    private static func pruneOrphanedAccountsOnce() {
        guard !didPruneOrphanedAccounts else { return }

        didPruneOrphanedAccounts = true
        let known = Set(AccountsStore.shared.accounts.map(\.id))
        let orphans: Set<UUID> = enrichmentLock.withLock {
            let orphans = Set(indexedPadIdentifiersByAccount.keys)
                .union(indexedQuestionIdentifiersByAccount.keys)
                .subtracting(known)
            guard !orphans.isEmpty else { return [] }

            for orphan in orphans {
                indexedPadIdentifiersByAccount.removeValue(forKey: orphan)
                indexedQuestionIdentifiersByAccount.removeValue(forKey: orphan)
            }
            persistPadIdentifiers()
            persistQuestionIdentifiers()
            return orphans
        }
        for orphan in orphans {
            enqueueDelete(operation: "remove orphaned account domain") { completion in
                CSSearchableIndex.default().deleteSearchableItems(
                    withDomainIdentifiers: [domain(orphan)],
                    completionHandler: completion
                )
            }
        }
    }

    private nonisolated static func reconcilePadIdentifiers(_ current: Set<String>, account: UUID) {
        let stale = enrichmentLock.withLock {
            let stale = (indexedPadIdentifiersByAccount[account] ?? []).subtracting(current)
            indexedPadIdentifiersByAccount[account] = current
            persistPadIdentifiers()
            return stale
        }
        deleteStaleIdentifiers(stale, operation: "remove stale pad items")
    }

    private nonisolated static func reconcileQuestionIdentifiers(_ current: Set<String>, account: UUID) {
        let stale = enrichmentLock.withLock {
            let stale = (indexedQuestionIdentifiersByAccount[account] ?? []).subtracting(current)
            indexedQuestionIdentifiersByAccount[account] = current
            persistQuestionIdentifiers()
            // Invalidate any in-flight keyword enrichment for the reconciled-away
            // questions (as removeQuestion does): a slow enrichment from the previous
            // pass would otherwise re-index the item AFTER the delete below, and with
            // the identifier gone from the bookkeeping set no later reconcile would
            // ever detect it again - a permanent Spotlight resurrection (#1021).
            for identifier in stale {
                questionEnrichmentGenerations.removeValue(forKey: identifier)
                enrichedQuestionFingerprints.removeValue(forKey: identifier)
            }
            return stale
        }
        deleteStaleIdentifiers(stale, operation: "remove stale question items")
    }

    private nonisolated static func deleteStaleIdentifiers(_ identifiers: Set<String>, operation: String) {
        guard !identifiers.isEmpty else { return }

        enqueueDelete(operation: operation) { completion in
            CSSearchableIndex.default().deleteSearchableItems(
                withIdentifiers: Array(identifiers),
                completionHandler: completion
            )
        }
    }

    @MainActor
    static func accountStillExists(_ account: UUID) -> Bool {
        AccountsStore.shared.accounts.contains { $0.id == account }
    }

    /// Removes all indexed items for an account (e.g. when it's deleted).
    static func removeAccount(_ account: UUID) {
        invalidateQuestionEnrichment(account: account)
        enrichmentLock.withLock {
            indexedPadIdentifiersByAccount.removeValue(forKey: account)
            indexedQuestionIdentifiersByAccount.removeValue(forKey: account)
            persistPadIdentifiers()
            persistQuestionIdentifiers()
        }
        enqueueDelete(operation: "remove account domain") { completion in
            CSSearchableIndex.default().deleteSearchableItems(
                withDomainIdentifiers: [domain(account)],
                completionHandler: completion
            )
        }
    }

    /// Clears everything this app indexed — used when the user turns the feature off.
    static func clearAll() {
        enrichmentLock.withLock {
            indexedPadIdentifiersByAccount.removeAll()
            indexedQuestionIdentifiersByAccount.removeAll()
            questionEnrichmentGenerations.removeAll()
            enrichedQuestionFingerprints.removeAll()
            UserDefaults.standard.removeObject(forKey: PersistenceKey.pads)
            UserDefaults.standard.removeObject(forKey: PersistenceKey.questions)
        }
        enqueueDelete(operation: "clear all items") { completion in
            CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: completion)
        }
    }

    /// How many records one CoreSpotlight write carries. Mapping an entire large
    /// org into `CSSearchableItem`s up front spiked memory; chunking builds each
    /// batch's items inside its own queued operation instead (#1729).
    private nonisolated static let indexChunkSize = 500

    private nonisolated static func indexChunked<Record: Sendable>(
        _ records: [Record],
        makeItem: @escaping @Sendable (Record) -> CSSearchableItem
    ) {
        var start = 0
        while start < records.count {
            let chunk = Array(records[start ..< min(start + indexChunkSize, records.count)])
            enqueueSpotlightOperation { finish in
                guard UserDefaults.standard.bool(forKey: GeneralSettings.Key.spotlightIndexing) else {
                    finish()
                    return
                }

                CSSearchableIndex.default().indexSearchableItems(chunk.map(makeItem)) { error in
                    if let error {
                        logger.error("Spotlight index failed: \(error.localizedDescription, privacy: .private)")
                    }
                    finish()
                }
            }
            start += indexChunkSize
        }
    }

    static func index(_ items: [CSSearchableItem]) {
        guard !items.isEmpty else { return }

        enqueueSpotlightOperation { finish in
            // Re-checked at execution time, not just at enqueue: a slow keyword
            // enrichment can enqueue an index write after the user opted out, and
            // that write would run after clearAll() and repopulate the index (#734).
            // The preference flips before clearAll is enqueued, so any operation
            // ordered after the clear sees it off and skips. Read straight from
            // UserDefaults (thread-safe) since this runs off the MainActor.
            guard UserDefaults.standard.bool(forKey: GeneralSettings.Key.spotlightIndexing) else {
                finish()
                return
            }

            CSSearchableIndex.default().indexSearchableItems(items) { error in
                if let error {
                    // `.private`: system error text can echo identifiers (#1735).
                    logger.error("Spotlight index failed: \(error.localizedDescription, privacy: .private)")
                }
                finish()
            }
        }
    }

    nonisolated static func enqueueDelete(
        operation: String,
        _ body: @escaping @Sendable (@escaping SpotlightErrorCompletion) -> Void
    ) {
        enqueueSpotlightOperation { finish in
            body { error in
                logDeletionFailure(error, operation: operation)
                finish()
            }
        }
    }

    private nonisolated static func enqueueSpotlightOperation(_ body: @escaping SpotlightOperation) {
        operationQueue.async {
            let semaphore = DispatchSemaphore(value: 0)
            body { semaphore.signal() }
            // Bounded wait: a CoreSpotlight completion that never arrives must not
            // wedge every later index/delete operation forever (#1730).
            if semaphore.wait(timeout: .now() + 30) == .timedOut {
                logger.error("Spotlight operation timed out after 30s; continuing with the next operation")
            }
        }
    }

    private nonisolated static func logDeletionFailure(_ error: (any Error)?, operation: String) {
        guard let error else { return }

        // `.private` for the error text: it can echo identifiers (#1735).
        logger.error("""
        Spotlight delete failed for \(operation, privacy: .public): \
        \(error.localizedDescription, privacy: .private)
        """)
    }
}

// The single-item removals and the indexed-identifier persistence live in
// SpotlightIndexer+Removals.swift; the on-device keyword enrichment in
// SpotlightIndexer+Enrichment.swift (both split for the length lints).
