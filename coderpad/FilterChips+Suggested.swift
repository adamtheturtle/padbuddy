//
//  FilterChips+Suggested.swift
//  coderpad
//
//  The built-in Suggested-search chips. Split out of FilterChips.swift so each
//  chip family keeps its own file.
//

import SwiftUI

/// A built-in Suggested search shown as a chip. Defaults aren't persisted or
/// deletable — they're recomputed per account so "My Pads" and "My Questions"
/// track whoever is signed in.
struct DefaultSearch: Identifiable {
    let id: String
    let icon: String
    let search: NamedSearch
}

extension DefaultSearch {
    /// Built-in Suggested pad searches, recomputed per account. "My Pads" appears
    /// only when the account knows its user's email;
    /// "Active" filters to in-progress sessions (the API's "started" state). Shared
    /// by the pad chip bar and the sidebar so the two never drift.
    static func padDefaults(me currentUserEmail: String?) -> [DefaultSearch] {
        var result: [DefaultSearch] = []
        if let currentUserEmail, !currentUserEmail.isEmpty {
            result.append(DefaultSearch(
                id: "my-pads", icon: "person.fill",
                search: NamedSearch(name: String(localized: "My Pads"), ownerFilter: currentUserEmail)
            ))
        }
        result.append(DefaultSearch(id: "active", icon: "bolt.fill",
                                    search: NamedSearch(name: String(localized: "Active"), stateFilter: .active)))
        return result
    }

    /// Built-in Suggested question searches, recomputed per account. "My Questions"
    /// appears only when the account knows
    /// its user's email; "Drafts" filters to unpublished questions. Shared by the
    /// question chip bar and the sidebar so the two never drift.
    static func questionDefaults(me currentUserEmail: String?) -> [DefaultSearch] {
        var result: [DefaultSearch] = []
        if let currentUserEmail, !currentUserEmail.isEmpty {
            result.append(DefaultSearch(
                id: "my-questions", icon: "person.fill",
                search: NamedSearch(name: String(localized: "My Questions"), ownerFilter: currentUserEmail)
            ))
        }
        result.append(DefaultSearch(id: "drafts", icon: "doc.badge.ellipsis",
                                    search: NamedSearch(name: String(localized: "Drafts"), draftFilter: "draft")))
        return result
    }
}

// `SavedSearchChip` now lives in `BuddyDesignSystem` (#649), re-exported via
// `DesignSystem.swift`, so the chip bars keep using it unqualified. Call sites pass
// `maxNameLength: NamedSearch.maxNameLength` to keep the clamp wired to the app constant.
