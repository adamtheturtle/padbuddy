//
//  SpotlightIndexer+Identifiers.swift
//  coderpad
//
//  The stateless halves of SpotlightIndexer: parsing result identifiers back into
//  pad/question references, and the plist encoding of the indexed-identifier
//  bookkeeping that lets stale-item reconciliation span launches (#733).
//

import Foundation

// MARK: - Result-identifier parsing

extension SpotlightIndexer {
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

// MARK: - Indexed-identifier plist encoding (#733)

extension SpotlightIndexer {
    /// The plist-safe encoding of an identifier map stored in UserDefaults.
    /// Internal rather than private so tests can pin the round-trip.
    nonisolated static func encodeIdentifierMap(_ map: [UUID: Set<String>]) -> [String: [String]] {
        map.reduce(into: [:]) { $0[$1.key.uuidString] = $1.value.sorted() }
    }

    nonisolated static func decodeIdentifierMap(_ raw: [String: [String]]) -> [UUID: Set<String>] {
        raw.reduce(into: [:]) { result, entry in
            guard let uuid = UUID(uuidString: entry.key) else { return }

            result[uuid] = Set(entry.value)
        }
    }

    nonisolated static func loadPersistedIdentifiers(key: String) -> [UUID: Set<String>] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] else { return [:] }

        return decodeIdentifierMap(raw)
    }
}
