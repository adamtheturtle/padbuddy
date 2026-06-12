//
//  SpotlightIndexer.swift
//  coderpad
//

import CoreSpotlight
import Foundation
import UniformTypeIdentifiers
import os.log

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
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "spotlight")
    private static let padPrefix = "pad:"
    private static let questionPrefix = "question:"

    private static func domain(_ account: UUID) -> String { account.uuidString }

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
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            return CSSearchableItem(uniqueIdentifier: questionPrefix + String(question.id),
                                    domainIdentifier: domain(account),
                                    attributeSet: attrs)
        }
        index(items)
    }

    /// Removes all indexed items for an account (e.g. when it's deleted).
    static func removeAccount(_ account: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain(account)])
    }

    /// Clears everything this app indexed — used when the user turns the feature off.
    static func clearAll() {
        CSSearchableIndex.default().deleteAllSearchableItems()
    }

    private static func index(_ items: [CSSearchableItem]) {
        guard !items.isEmpty else { return }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error {
                logger.error("Spotlight index failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The pad id encoded in a Spotlight result identifier, or `nil` if it isn't a pad.
    static func padID(fromItemIdentifier id: String) -> String? {
        id.hasPrefix(padPrefix) ? String(id.dropFirst(padPrefix.count)) : nil
    }

    /// Whether a Spotlight result identifier refers to a question.
    static func isQuestion(itemIdentifier id: String) -> Bool {
        id.hasPrefix(questionPrefix)
    }
}
