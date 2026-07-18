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
    private typealias SpotlightErrorCompletion = @Sendable ((any Error)?) -> Void
    private typealias SpotlightOperation = @Sendable (@escaping SpotlightFinish) -> Void

    private nonisolated static let operationQueue = DispatchQueue(label: "com.coderpad.app.spotlight.operations")
    private nonisolated static let enrichmentLock = NSLock()
    private nonisolated(unsafe) static var questionEnrichmentGenerations: [String: Int] = [:]
    // Seeded from UserDefaults so reconciliation spans launches: an item deleted
    // server-side while the app was closed must still be detected as stale on the
    // first refresh after relaunch, or it lingers in system search forever (#733).
    private nonisolated(unsafe) static var indexedPadIdentifiersByAccount: [UUID: Set<String>] =
        loadPersistedIdentifiers(key: PersistenceKey.pads)
    private nonisolated(unsafe) static var indexedQuestionIdentifiersByAccount: [UUID: Set<String>] =
        loadPersistedIdentifiers(key: PersistenceKey.questions)

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
    private static let maxKeywordEnrichments = 50

    private nonisolated static func domain(_ account: UUID) -> String {
        account.uuidString
    }

    /// A question's Spotlight identifier. Question ids are numbered *per org* and
    /// collide across accounts, while `uniqueIdentifier` is a global key — so it's
    /// namespaced with the account UUID (`question:<uuid>:<id>`). Without this,
    /// indexing one account's question overwrites another's same-id entry, and a
    /// single-account delete removes the other account's item too (#378). (Pads use
    /// global slug ids, so they need no such namespacing.)
    private nonisolated static func questionIdentifier(id: Int, account: UUID) -> String {
        "\(questionPrefix)\(account.uuidString):\(id)"
    }

    /// Indexes (or re-indexes) the account's pads. No-op unless the user enabled it.
    static func updatePads(_ pads: [Pad], account: UUID) {
        guard GeneralSettings.spotlightIndexing else { return }

        let identifiers = Set(pads.map { padIdentifier(id: $0.id, account: account) })
        reconcilePadIdentifiers(identifiers, account: account)

        let items = pads.map { pad -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = pad.title.isEmpty ? pad.id : pad.title
            attrs.contentDescription = [pad.status.label, pad.ownerEmail]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return CSSearchableItem(uniqueIdentifier: padIdentifier(id: pad.id, account: account),
                                    domainIdentifier: domain(account),
                                    attributeSet: attrs)
        }
        index(items)
    }

    /// Indexes (or re-indexes) the account's questions. No-op unless enabled.
    static func updateQuestions(_ questions: [Question], account: UUID) {
        guard GeneralSettings.spotlightIndexing else { return }

        let identifiers = Set(questions.map { questionIdentifier(id: $0.id, account: account) })
        reconcileQuestionIdentifiers(identifiers, account: account)

        let items = questions.map { question -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = question.title.isEmpty ? "#\(question.id)" : question.title
            attrs.contentDescription = [question.language, question.authorName]
                .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
            return CSSearchableItem(uniqueIdentifier: questionIdentifier(id: question.id, account: account),
                                    domainIdentifier: domain(account),
                                    attributeSet: attrs)
        }
        index(items)
        enrichQuestionKeywords(questions, account: account)
    }

    /// Re-indexes a bounded set of questions with on-device-generated keywords so
    /// Spotlight finds them by topic, not just by words in their title. Runs only
    /// when the model is available and indexing is on, on top of the items already
    /// indexed above — so it never indexes anything the user didn't opt into. The
    /// indexing-on gate is re-checked per item so turning the feature off mid-pass
    /// stops adding more.
    private static func enrichQuestionKeywords(_ questions: [Question], account: UUID) {
        guard SpotlightSummarizer.isAvailable else { return }

        let candidates = questions.filter { ($0.description?.isEmpty == false) }
        guard !candidates.isEmpty else { return }

        let bounded = Array(candidates.prefix(maxKeywordEnrichments))
        if candidates.count > bounded.count {
            logger.info(
                """
                Spotlight keyword enrichment limited to \
                \(maxKeywordEnrichments, privacy: .public) of \
                \(candidates.count, privacy: .public) questions this pass
                """
            )
        }
        let generationByIdentifier = Dictionary(uniqueKeysWithValues: bounded.map { question in
            let identifier = questionIdentifier(id: question.id, account: account)
            return (identifier, nextQuestionEnrichmentGeneration(for: identifier))
        })

        Task {
            for question in bounded {
                guard GeneralSettings.spotlightIndexing else { return }

                let identifier = questionIdentifier(id: question.id, account: account)
                guard let generation = generationByIdentifier[identifier] else { continue }
                guard let keywords = await SpotlightSummarizer.keywords(
                    title: question.title,
                    language: question.language,
                    description: question.description ?? ""
                ) else { continue }
                guard isCurrentQuestionEnrichment(identifier: identifier, generation: generation) else { continue }
                guard accountStillExists(account) else { continue }

                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = question.title.isEmpty ? "#\(question.id)" : question.title
                attrs.contentDescription = [question.language, question.authorName]
                    .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
                attrs.keywords = keywords
                let item = CSSearchableItem(uniqueIdentifier: identifier,
                                            domainIdentifier: domain(account),
                                            attributeSet: attrs)
                index([item])
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

    private nonisolated static func nextQuestionEnrichmentGeneration(for identifier: String) -> Int {
        enrichmentLock.withLock {
            let next = (questionEnrichmentGenerations[identifier] ?? 0) + 1
            questionEnrichmentGenerations[identifier] = next
            return next
        }
    }

    private nonisolated static func isCurrentQuestionEnrichment(identifier: String, generation: Int) -> Bool {
        enrichmentLock.withLock {
            questionEnrichmentGenerations[identifier] == generation
        }
    }

    private nonisolated static func invalidateQuestionEnrichment(account: UUID) {
        let prefix = "\(questionPrefix)\(account.uuidString):"
        enrichmentLock.withLock {
            questionEnrichmentGenerations = questionEnrichmentGenerations.filter { !$0.key.hasPrefix(prefix) }
        }
    }

    @MainActor
    private static func accountStillExists(_ account: UUID) -> Bool {
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
            UserDefaults.standard.removeObject(forKey: PersistenceKey.pads)
            UserDefaults.standard.removeObject(forKey: PersistenceKey.questions)
        }
        enqueueDelete(operation: "clear all items") { completion in
            CSSearchableIndex.default().deleteAllSearchableItems(completionHandler: completion)
        }
    }

    private static func index(_ items: [CSSearchableItem]) {
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
                    logger.error("Spotlight index failed: \(error.localizedDescription, privacy: .public)")
                }
                finish()
            }
        }
    }

    private nonisolated static func enqueueDelete(
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
            semaphore.wait()
        }
    }

    private nonisolated static func logDeletionFailure(_ error: (any Error)?, operation: String) {
        guard let error else { return }

        logger.error("""
        Spotlight delete failed for \(operation, privacy: .public): \
        \(error.localizedDescription, privacy: .public)
        """)
    }

}

// MARK: - Single-item removals

extension SpotlightIndexer {
    /// Removes a single pad from the index (e.g. when it's deleted). Re-indexing
    /// the remaining list only adds/updates items, so a dropped pad needs an
    /// explicit delete by identifier or it lingers in system search. Deletes the
    /// pad's namespaced identifier for every account that holds it, plus the legacy
    /// global form so pre-#759 items indexed before the namespacing are cleaned too.
    static func removePad(id: String) {
        let identifiers: [String] = enrichmentLock.withLock {
            var identifiers = [padPrefix + id]
            for account in indexedPadIdentifiersByAccount.keys {
                identifiers.append(padIdentifier(id: id, account: account))
            }
            for (account, held) in indexedPadIdentifiersByAccount {
                indexedPadIdentifiersByAccount[account] = held.subtracting(identifiers)
            }
            persistPadIdentifiers()
            return identifiers
        }
        enqueueDelete(operation: "remove pad item") { completion in
            CSSearchableIndex.default().deleteSearchableItems(
                withIdentifiers: identifiers,
                completionHandler: completion
            )
        }
    }

    /// Account-scoped variant of ``removePad(id:)``: deletes only the owning
    /// account's namespaced identifier (plus the legacy global form, which predates
    /// the namespacing), so a deletion in one account can't drop a colliding slug
    /// another custom server issued (#761).
    static func removePad(id: String, account: UUID) {
        let identifiers = [padIdentifier(id: id, account: account), padPrefix + id]
        enrichmentLock.withLock {
            indexedPadIdentifiersByAccount[account]?.subtract(identifiers)
            persistPadIdentifiers()
        }
        enqueueDelete(operation: "remove pad item") { completion in
            CSSearchableIndex.default().deleteSearchableItems(
                withIdentifiers: identifiers,
                completionHandler: completion
            )
        }
    }

    /// Removes a single question from the index (e.g. when it's deleted). Scoped to
    /// the owning account so a delete in one account can't drop another account's
    /// same-id question from system search (#378).
    static func removeQuestion(id: Int, account: UUID) {
        let identifier = questionIdentifier(id: id, account: account)
        enrichmentLock.withLock {
            indexedQuestionIdentifiersByAccount[account]?.remove(identifier)
            questionEnrichmentGenerations.removeValue(forKey: identifier)
            persistQuestionIdentifiers()
        }
        enqueueDelete(operation: "remove question item") { completion in
            CSSearchableIndex.default()
                .deleteSearchableItems(
                    withIdentifiers: [identifier],
                    completionHandler: completion
                )
        }
    }
}

// MARK: - Indexed-identifier bookkeeping persistence (#733)

extension SpotlightIndexer {
    /// Both persist helpers must be called while holding `enrichmentLock`,
    /// alongside the in-memory mutation they mirror. The stateless
    /// encode/decode/load halves live in `SpotlightIndexer+Identifiers.swift`.
    private nonisolated static func persistPadIdentifiers() {
        UserDefaults.standard.set(encodeIdentifierMap(indexedPadIdentifiersByAccount),
                                  forKey: PersistenceKey.pads)
    }

    private nonisolated static func persistQuestionIdentifiers() {
        UserDefaults.standard.set(encodeIdentifierMap(indexedQuestionIdentifiersByAccount),
                                  forKey: PersistenceKey.questions)
    }
}
