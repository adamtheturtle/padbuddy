//
//  SpotlightIndexer+Enrichment.swift
//  coderpad
//
//  The on-device keyword enrichment half of SpotlightIndexer, split from
//  SpotlightIndexer.swift to keep it within the lint length limits.
//

@preconcurrency import CoreSpotlight
import Foundation

extension SpotlightIndexer {
    /// One scheduled enrichment: the question, its Spotlight identifier, and the
    /// generation guarding its publish.
    private struct EnrichmentCandidate {
        let question: Question
        let identifier: String
        let generation: Int
        let fingerprint: Int
    }

    /// Re-indexes a bounded set of questions with on-device-generated keywords so
    /// Spotlight finds them by topic, not just by words in their title. Runs only
    /// when the model is available and indexing is on, on top of the items already
    /// indexed above — so it never indexes anything the user didn't opt into. The
    /// indexing-on gate is re-checked per item so turning the feature off mid-pass
    /// stops adding more.
    static func enrichQuestionKeywords(_ questions: [Question], account: UUID) {
        guard SpotlightSummarizer.isAvailable else { return }

        // Only genuinely enrichable questions count: a whitespace-only description
        // would run the model just to return nil (#1726), and questions whose
        // content fingerprint was already scheduled don't re-run on refreshes
        // (#1725) — which also means the cap counts only *new* work, so a large
        // org's tail gets reached on later passes instead of starving (#1724).
        let enrichable = questions.filter {
            !($0.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let candidates: [EnrichmentCandidate] = enrichmentLock.withLock {
            let fresh = enrichable.filter { question in
                let identifier = questionIdentifier(id: question.id, account: account)
                // Not already enriched for this content, and not already claimed by a
                // pass still running.
                return enrichedQuestionFingerprints[identifier] != questionFingerprint(question)
                    && questionEnrichmentGenerations[identifier] == nil
            }
            return fresh.prefix(maxKeywordEnrichments).map { question in
                let identifier = questionIdentifier(id: question.id, account: account)
                // Claimed, not recorded as enriched: the fingerprint used to be written
                // here, so a model returning nil, a cancelled or superseded pass, a
                // removed account, or a failed index left the question marked as done
                // and it was filtered out of every later pass forever (#4686). It is
                // written after the item is actually handed to Spotlight instead.
                enrichmentGenerationCounter &+= 1
                questionEnrichmentGenerations[identifier] = enrichmentGenerationCounter
                return EnrichmentCandidate(question: question, identifier: identifier,
                                           generation: enrichmentGenerationCounter,
                                           fingerprint: questionFingerprint(question))
            }
        }
        guard !candidates.isEmpty else { return }

        // Replaces any pass still running for this account rather than stacking a
        // second one alongside it (#2409). Candidates already claimed by the
        // superseded pass keep their fingerprints, so they are not re-run here; the
        // generation guard below drops any write it had in flight.
        let task = Task {
            for candidate in candidates {
                guard !Task.isCancelled, GeneralSettings.spotlightIndexing else { return }

                let question = candidate.question
                defer {
                    finishQuestionEnrichment(identifier: candidate.identifier,
                                             generation: candidate.generation)
                }
                guard let keywords = await SpotlightSummarizer.keywords(
                    title: question.title,
                    language: question.language,
                    description: question.description ?? ""
                ) else { continue }
                guard isCurrentQuestionEnrichment(identifier: candidate.identifier,
                                                  generation: candidate.generation) else { continue }
                guard accountStillExists(account) else { continue }

                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = presentableTitle(question.title, fallback: "#\(question.id)")
                attrs.contentDescription = question.language ?? ""
                attrs.keywords = keywords
                let item = CSSearchableItem(uniqueIdentifier: candidate.identifier,
                                            domainIdentifier: domain(account),
                                            attributeSet: attrs)
                index([item])
                // Only now is this content genuinely enriched, so only now is it worth
                // skipping on a later pass.
                enrichmentLock.withLock {
                    enrichedQuestionFingerprints[candidate.identifier] = candidate.fingerprint
                }
            }
        }
        replaceEnrichmentTask(task, account: account)
    }

    /// Installs `task` as the account's running pass and cancels the one it replaces.
    private nonisolated static func replaceEnrichmentTask(_ task: Task<Void, Never>, account: UUID) {
        let superseded: Task<Void, Never>? = enrichmentLock.withLock {
            let previous = enrichmentTasks[account]
            enrichmentTasks[account] = task
            return previous
        }
        superseded?.cancel()
    }

    /// Stops every running enrichment pass — used when the user turns Spotlight
    /// indexing off, so an opt-out takes effect immediately rather than after the
    /// current batch of model calls drains (#2409).
    nonisolated static func cancelEnrichment() {
        let running: [Task<Void, Never>] = enrichmentLock.withLock {
            let tasks = Array(enrichmentTasks.values)
            enrichmentTasks.removeAll()
            return tasks
        }
        for task in running {
            task.cancel()
        }
    }

    /// The content identity an enrichment was generated for; a changed title,
    /// language, or description re-enriches, an unchanged one doesn't (#1725).
    nonisolated static func questionFingerprint(_ question: Question) -> Int {
        var hasher = Hasher()
        hasher.combine(question.title)
        hasher.combine(question.language)
        hasher.combine(question.description)
        return hasher.finalize()
    }

    private nonisolated static func isCurrentQuestionEnrichment(identifier: String, generation: Int) -> Bool {
        enrichmentLock.withLock {
            questionEnrichmentGenerations[identifier] == generation
        }
    }

    /// Clears a completed enrichment's generation entry (when it still owns it),
    /// so the map holds only in-flight work instead of growing for every question
    /// ever viewed (#1727). Generations come from a monotonic counter, so a
    /// cleaned-up value can never be reissued to a later pass.
    private nonisolated static func finishQuestionEnrichment(identifier: String, generation: Int) {
        enrichmentLock.withLock {
            if questionEnrichmentGenerations[identifier] == generation {
                questionEnrichmentGenerations.removeValue(forKey: identifier)
            }
        }
    }

    nonisolated static func invalidateQuestionEnrichment(account: UUID) {
        let prefix = "\(questionPrefix)\(account.uuidString):"
        enrichmentLock.withLock {
            questionEnrichmentGenerations = questionEnrichmentGenerations.filter { !$0.key.hasPrefix(prefix) }
            enrichedQuestionFingerprints = enrichedQuestionFingerprints.filter { !$0.key.hasPrefix(prefix) }
        }
    }
}
