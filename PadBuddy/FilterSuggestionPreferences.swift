//
//  FilterSuggestionPreferences.swift
//  coderpad
//

import Foundation

@MainActor
@Observable
final class FilterSuggestionPreferences {
    static let shared = FilterSuggestionPreferences()
    private(set) var revision = 0
    private let prefix = "dismissedFilterSuggestions.v1"

    private init() {}

    /// The built-in suggestions that can be dismissed. The dismissal list is per account
    /// and is read on every chip-bar and sidebar evaluation, so accepting any string let
    /// it grow without bound and made each visibility check hash an ever-larger set
    /// (#4576). Only ids that name a real suggestion are worth remembering.
    static func knownIDs(kind: SavedSearchKind) -> Set<String> {
        switch kind {
        case .pads: ["my-pads", "active"]
        case .questions: ["my-questions", "drafts"]
        }
    }

    func isVisible(_ id: String, kind: SavedSearchKind, account: UUID?) -> Bool {
        guard let account else { return true }

        return !dismissed(kind: kind, account: account).contains(id)
    }

    func dismiss(_ id: String, kind: SavedSearchKind, account: UUID) {
        guard Self.knownIDs(kind: kind).contains(id) else { return }

        var values = dismissed(kind: kind, account: account)
        guard values.insert(id).inserted else { return }

        UserDefaults.standard.set(values.sorted(), forKey: key(kind: kind, account: account))
        revision &+= 1
    }

    /// Drops a removed account's dismissals, so a reused identifier does not inherit
    /// suggestions hidden by whoever held it before.
    func removeDismissals(account: UUID) {
        for kind in [SavedSearchKind.pads, .questions] {
            UserDefaults.standard.removeObject(forKey: key(kind: kind, account: account))
        }
        revision &+= 1
    }

    private func dismissed(kind: SavedSearchKind, account: UUID) -> Set<String> {
        let stored = UserDefaults.standard.stringArray(forKey: key(kind: kind, account: account)) ?? []
        let known = Self.knownIDs(kind: kind)
        let kept = Set(stored).intersection(known)
        // Prune anything a previous build (or a corrupt default) left behind, so the list
        // shrinks to the bounded set rather than being re-read at full size forever.
        if kept.count != stored.count {
            let storageKey = key(kind: kind, account: account)
            if kept.isEmpty {
                UserDefaults.standard.removeObject(forKey: storageKey)
            } else {
                UserDefaults.standard.set(kept.sorted(), forKey: storageKey)
            }
        }
        return kept
    }

    private func key(kind: SavedSearchKind, account: UUID) -> String {
        "\(prefix).\(kind.rawValue).\(account.uuidString)"
    }
}
