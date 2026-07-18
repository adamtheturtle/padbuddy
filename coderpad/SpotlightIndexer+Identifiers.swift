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
    /// The Spotlight identifier for one pad. Namespaced with the account UUID like
    /// questions (#378): pad slugs are only unique within one server, so two custom
    /// CoderPad servers can issue the same slug — a global `pad:<slug>` identifier let
    /// one account's item overwrite the other's, and a single delete removed both
    /// (#759). Old-format identifiers are reconciled away by the persisted-identifier
    /// bookkeeping on the next index pass.
    nonisolated static func padIdentifier(id: String, account: UUID) -> String {
        "\(padPrefix)\(account.uuidString):\(id)"
    }

    /// The account and pad id encoded in a Spotlight result identifier, or `nil` if it
    /// isn't a pad. New items are account-namespaced (`pad:<uuid>:<slug>`) so a result
    /// can be routed to the server that owns it — slugs collide across custom servers
    /// (#759). Items indexed before the namespacing carry no account (`pad:<slug>`)
    /// and yield a nil account, keeping old taps working until they're reconciled.
    static func padRef(fromItemIdentifier id: String) -> (account: UUID?, id: String)? {
        guard id.hasPrefix(padPrefix) else { return nil }

        let body = id.dropFirst(padPrefix.count)
        guard !body.isEmpty else { return nil }
        if let separator = body.firstIndex(of: ":"),
           let account = UUID(uuidString: String(body[..<separator])),
           body.index(after: separator) < body.endIndex {
            return (account, String(body[body.index(after: separator)...]))
        }
        return (nil, String(body))
    }

    /// The bare pad id of a result identifier, for callers that don't route by
    /// account. Prefer ``padRef(fromItemIdentifier:)``, which carries the owning
    /// account for namespaced items (#759).
    static func padID(fromItemIdentifier id: String) -> String? {
        padRef(fromItemIdentifier: id)?.id
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
