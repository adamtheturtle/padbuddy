//
//  SpotlightIndexer+Removals.swift
//  coderpad
//
//  Single-item removals and the indexed-identifier bookkeeping persistence,
//  split from SpotlightIndexer.swift to keep it within the lint length limits.
//

@preconcurrency import CoreSpotlight
import Foundation

// MARK: - Single-item removals

extension SpotlightIndexer {
    /// Deletes only the owning account's namespaced identifier plus the legacy
    /// global form, which predates
    /// the namespacing), so a deletion in one account can't drop a colliding slug
    /// another custom server issued (#761).
    static func removePad(id: String, account: UUID) {
        let identifiers = [padIdentifier(id: id, account: account), padPrefix + id]
        enrichmentLock.withLock {
            indexedPadIdentifiersByAccount[account]?.subtract(identifiers)
            for identifier in identifiers {
                indexedPadFingerprints.removeValue(forKey: identifier)
            }
            persistPadIdentifiers()
        }
        enqueueDelete(operation: "remove pad item") { completion in
            CSSearchableIndex.default().deleteSearchableItems(
                withIdentifiers: identifiers,
                completionHandler: completion
            )
        }
    }

    /// the owning account so a delete in one account can't drop another account's
    /// the owning account so a delete in one account cannot drop another account's
    /// same-id question from system search (#378).
    static func removeQuestion(id: Int, account: UUID) {
        let identifier = questionIdentifier(id: id, account: account)
        enrichmentLock.withLock {
            indexedQuestionIdentifiersByAccount[account]?.remove(identifier)
            indexedQuestionFingerprints.removeValue(forKey: identifier)
            questionEnrichmentGenerations.removeValue(forKey: identifier)
            enrichedQuestionFingerprints.removeValue(forKey: identifier)
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
    /// Coalesces mutation bursts, then snapshots, encodes, and writes off the
    /// caller's thread.
    ///
    /// These are called with `enrichmentLock` held, and the maps can hold an
    /// identifier per pad and per question across every account — so encoding *and*
    /// the `UserDefaults` write happened under the lock, blocking enrichment,
    /// removal, and any UI-triggered update behind a large serialization (#2418).
    /// A short coalescing window turns a bulk reconciliation or deletion burst into
    /// one full-map sort/plist write instead of one per item (#2133).
    nonisolated static func persistPadIdentifiers() {
        guard !padPersistencePending else { return }

        padPersistencePending = true
        persistenceQueue.asyncAfter(deadline: .now() + persistenceDelay) {
            let encoded = enrichmentLock.withLock {
                padPersistencePending = false
                return encodeIdentifierMap(indexedPadIdentifiersByAccount)
            }
            UserDefaults.standard.set(encoded, forKey: PersistenceKey.pads)
        }
    }

    nonisolated static func persistQuestionIdentifiers() {
        guard !questionPersistencePending else { return }

        questionPersistencePending = true
        persistenceQueue.asyncAfter(deadline: .now() + persistenceDelay) {
            let encoded = enrichmentLock.withLock {
                questionPersistencePending = false
                return encodeIdentifierMap(indexedQuestionIdentifiersByAccount)
            }
            UserDefaults.standard.set(encoded, forKey: PersistenceKey.questions)
        }
    }

    /// Protected by `enrichmentLock`, like the identifier maps they represent.
    private nonisolated(unsafe) static var padPersistencePending = false
    private nonisolated(unsafe) static var questionPersistencePending = false
    private nonisolated static let persistenceDelay = DispatchTimeInterval.milliseconds(200)

    /// Serial, so the two maps' writes stay ordered with respect to each other and
    /// to their own later rewrites.
    private nonisolated static let persistenceQueue = DispatchQueue(
        label: "com.coderpad.spotlight-identifier-persistence",
        qos: .utility
    )
}
