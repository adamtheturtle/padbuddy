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

    func isVisible(_ id: String, kind: SavedSearchKind, account: UUID?) -> Bool {
        guard let account else { return true }

        return !dismissed(kind: kind, account: account).contains(id)
    }

    func dismiss(_ id: String, kind: SavedSearchKind, account: UUID) {
        var values = dismissed(kind: kind, account: account)
        guard values.insert(id).inserted else { return }

        UserDefaults.standard.set(Array(values).sorted(), forKey: key(kind: kind, account: account))
        revision &+= 1
    }

    private func dismissed(kind: SavedSearchKind, account: UUID) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key(kind: kind, account: account)) ?? [])
    }

    private func key(kind: SavedSearchKind, account: UUID) -> String {
        "\(prefix).\(kind.rawValue).\(account.uuidString)"
    }
}
