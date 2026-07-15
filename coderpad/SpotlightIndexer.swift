//
//  SpotlightIndexer.swift
//  coderpad
//

import CoreSpotlight
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
    private static let padPrefix = "pad:"
    private static let questionPrefix = "question:"
    /// How many questions one indexing pass will enrich with on-device keywords.
    /// Each enrichment runs the language model, so a big org's full list would be
    /// far too costly to summarize in one go; the cap keeps it bounded and the
    /// dropped remainder is logged rather than silently skipped.
    private static let maxKeywordEnrichments = 50

    private static func domain(_ account: UUID) -> String {
        account.uuidString
    }

    /// A question's Spotlight identifier. Question ids are numbered *per org* and
    /// collide across accounts, while `uniqueIdentifier` is a global key — so it's
    /// namespaced with the account UUID (`question:<uuid>:<id>`). Without this,
    /// indexing one account's question overwrites another's same-id entry, and a
    /// single-account delete removes the other account's item too (#378). (Pads use
    /// global slug ids, so they need no such namespacing.)
    private static func questionIdentifier(id: Int, account: UUID) -> String {
        "\(questionPrefix)\(account.uuidString):\(id)"
    }

    /// Indexes (or re-indexes) the account's pads. No-op unless the user enabled it.
    static func updatePads(_ pads: [Pad], account: UUID) {
        guard GeneralSettings.spotlightIndexing else { return }

        let items = pads.map { pad -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = pad.title.isEmpty ? pad.id : pad.title
            attrs.contentDescription = [pad.status.label, pad.ownerEmail]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return CSSearchableItem(uniqueIdentifier: padPrefix + pad.id,
                                    domainIdentifier: domain(account),
                                    attributeSet: attrs)
        }
        index(items)
    }

    /// Indexes (or re-indexes) the account's questions. No-op unless enabled.
    static func updateQuestions(_ questions: [Question], account: UUID) {
        guard GeneralSettings.spotlightIndexing else { return }

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
        Task {
            for question in bounded {
                guard GeneralSettings.spotlightIndexing else { return }
                guard let keywords = await SpotlightSummarizer.keywords(
                    title: question.title,
                    language: question.language,
                    description: question.description ?? ""
                ) else { continue }

                let attrs = CSSearchableItemAttributeSet(contentType: .text)
                attrs.title = question.title.isEmpty ? "#\(question.id)" : question.title
                attrs.contentDescription = [question.language, question.authorName]
                    .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · ")
                attrs.keywords = keywords
                let item = CSSearchableItem(uniqueIdentifier: questionIdentifier(id: question.id, account: account),
                                            domainIdentifier: domain(account),
                                            attributeSet: attrs)
                index([item])
            }
        }
    }

    /// Removes all indexed items for an account (e.g. when it's deleted).
    static func removeAccount(_ account: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain(account)]) { error in
            logDeletionFailure(error, operation: "remove account domain")
        }
    }

    /// Removes a single pad from the index (e.g. when it's deleted). Re-indexing
    /// the remaining list only adds/updates items, so a dropped pad needs an
    /// explicit delete by identifier or it lingers in system search.
    static func removePad(id: String) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [padPrefix + id]) { error in
            logDeletionFailure(error, operation: "remove pad item")
        }
    }

    /// Removes a single question from the index (e.g. when it's deleted). Scoped to
    /// the owning account so a delete in one account can't drop another account's
    /// same-id question from system search (#378).
    static func removeQuestion(id: Int, account: UUID) {
        CSSearchableIndex.default()
            .deleteSearchableItems(withIdentifiers: [questionIdentifier(id: id, account: account)]) { error in
                logDeletionFailure(error, operation: "remove question item")
            }
    }

    /// Clears everything this app indexed — used when the user turns the feature off.
    static func clearAll() {
        CSSearchableIndex.default().deleteAllSearchableItems { error in
            logDeletionFailure(error, operation: "clear all items")
        }
    }

    private static func index(_ items: [CSSearchableItem]) {
        guard !items.isEmpty else { return }

        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                logger.error("Spotlight index failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private nonisolated static func logDeletionFailure(_ error: (any Error)?, operation: String) {
        guard let error else { return }

        logger.error("""
        Spotlight delete failed for \(operation, privacy: .public): \
        \(error.localizedDescription, privacy: .public)
        """)
    }

    /// The pad id encoded in a Spotlight result identifier, or `nil` if it isn't a pad.
    static func padID(fromItemIdentifier id: String) -> String? {
        id.hasPrefix(padPrefix) ? String(id.dropFirst(padPrefix.count)) : nil
    }

    /// Whether a Spotlight result identifier refers to a question.
    static func isQuestion(itemIdentifier id: String) -> Bool {
        id.hasPrefix(questionPrefix)
    }

    /// The account and question id encoded in a Spotlight result identifier, or
    /// `nil` if it isn't a (namespaced) question. Carrying the account lets the tap
    /// handler open the question in the right org rather than a colliding id in
    /// whichever account happens to be current (#378).
    static func questionRef(fromItemIdentifier id: String) -> (account: UUID, id: Int)? {
        guard id.hasPrefix(questionPrefix) else { return nil }

        let body = id.dropFirst(questionPrefix.count)
        guard let separator = body.firstIndex(of: ":"),
              let account = UUID(uuidString: String(body[..<separator])),
              let questionID = Int(body[body.index(after: separator)...]) else { return nil }

        return (account, questionID)
    }
}
