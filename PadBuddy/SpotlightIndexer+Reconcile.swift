//
//  SpotlightIndexer+Reconcile.swift
//  coderpad
//
//  Reconciling the persisted identifier maps against what the lists now hold,
//  and deleting what no longer belongs.
//

import CoreSpotlight
import Foundation
import os.log
import UniformTypeIdentifiers

extension SpotlightIndexer {
    nonisolated static func reconcilePadIdentifiers(_ current: Set<String>, account: UUID) {
        let generation = currentClearGeneration()
        let stale = enrichmentLock.withLock {
            let stale = (indexedPadIdentifiersByAccount[account] ?? []).subtracting(current)
            indexedPadIdentifiersByAccount[account] = current
            for identifier in stale {
                indexedPadFingerprints.removeValue(forKey: identifier)
            }
            persistPadIdentifiers()
            return stale
        }
        deleteStaleIdentifiers(stale, operation: "remove stale pad items") { failed in
            // The identifiers were dropped from the bookkeeping before the delete was
            // known to have worked, so a rejected deletion left the item searchable with
            // nothing left that remembered it existed — no later reconcile could ever
            // detect it again (#4684). Putting them back makes the next reconcile see
            // them as stale and try once more.
            enrichmentLock.withLock {
                guard isCurrentIndexStateLocked(generation: generation, account: account) else { return }

                indexedPadIdentifiersByAccount[account, default: []].formUnion(failed)
                persistPadIdentifiers()
            }
        }
    }

    nonisolated static func reconcileQuestionIdentifiers(_ current: Set<String>, account: UUID) {
        let generation = currentClearGeneration()
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
                indexedQuestionFingerprints.removeValue(forKey: identifier)
            }
            return stale
        }
        deleteStaleIdentifiers(stale, operation: "remove stale question items") { failed in
            // As for pads (#4684): a failed deletion keeps its bookkeeping so it retries.
            enrichmentLock.withLock {
                guard isCurrentIndexStateLocked(generation: generation, account: account) else { return }

                indexedQuestionIdentifiersByAccount[account, default: []].formUnion(failed)
                persistQuestionIdentifiers()
            }
        }
    }

    /// Deletes stale items, calling `onFailure` with the identifiers if Core Spotlight
    /// rejects the deletion so the caller can keep them for a later retry.
    private nonisolated static func deleteStaleIdentifiers(
        _ identifiers: Set<String>,
        operation: String,
        onFailure: @escaping @Sendable (Set<String>) -> Void
    ) {
        guard !identifiers.isEmpty else { return }

        enqueueDelete(operation: operation) { completion in
            CSSearchableIndex.default().deleteSearchableItems(
                withIdentifiers: Array(identifiers),
                completionHandler: { error in
                    if error != nil {
                        onFailure(identifiers)
                    }
                    completion(error)
                }
            )
        }
    }
}
