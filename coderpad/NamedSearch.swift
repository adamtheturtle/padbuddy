//
//  NamedSearch.swift
//  coderpad
//
//  Filter+search snapshot primitives shared by the pad and question lists: the
//  built-in Suggested searches, the live-filter persistence, and the sidebar's
//  "which search is applied" highlight signature all use these types.
//

import Foundation
import SwiftUI

/// A named filter+search snapshot. The fields are a superset across the pad and
/// question lists — pads use state/team/dateRange, questions use draft — so one
/// shape serves both. Unused fields stay `nil` for a given kind, and all are
/// optional so snapshots persisted before a field existed still decode.
struct NamedSearch: Identifiable, Codable, Hashable {
    /// The longest a search name may be. Names are short recall labels shown as
    /// chips, so capping them keeps any one chip from dominating the bar and
    /// guards against an accidental paste of a huge string. Chips clamp display so
    /// names persisted before the cap existed stay bounded.
    static let maxNameLength = 40

    let id: UUID
    var name: String
    var search: String
    var stateFilter: PadState?
    var languageFilter: String?
    var ownerFilter: String?
    var teamFilter: String?
    var typeFilter: String?
    /// Independent date constraints for the pad list: one applied to the updated
    /// date, one to the created date. Nil when the search has no such constraint.
    /// Optional so snapshots saved before these existed still decode.
    var updatedWindow: DateWindow?
    var createdWindow: DateWindow?
    var draftFilter: String?

    init(name: String,
         id: UUID = UUID(),
         search: String = "",
         stateFilter: PadState? = nil, languageFilter: String? = nil,
         ownerFilter: String? = nil, teamFilter: String? = nil,
         typeFilter: String? = nil,
         updatedWindow: DateWindow? = nil, createdWindow: DateWindow? = nil,
         draftFilter: String? = nil) {
        self.id = id
        self.name = name
        self.search = search
        self.stateFilter = stateFilter
        self.languageFilter = languageFilter
        self.ownerFilter = ownerFilter
        self.teamFilter = teamFilter
        self.typeFilter = typeFilter
        self.updatedWindow = updatedWindow
        self.createdWindow = createdWindow
        self.draftFilter = draftFilter
    }

    /// Whether two searches carry the same filter criteria, ignoring `id` and
    /// `name`. A live filter signature can be matched against a saved or built-in
    /// search regardless of how it was labeled, so the in-list chips and the
    /// sidebar share one definition of "this search is currently applied" and can
    /// never drift. Fields a given list doesn't use stay nil on both sides, so the
    /// full-field comparison is correct for both pads and questions.
    func hasSameFilters(as other: Self) -> Bool {
        search == other.search &&
            stateFilter == other.stateFilter &&
            languageFilter == other.languageFilter &&
            ownerFilter == other.ownerFilter &&
            teamFilter == other.teamFilter &&
            typeFilter == other.typeFilter &&
            updatedWindow == other.updatedWindow &&
            createdWindow == other.createdWindow &&
            draftFilter == other.draftFilter
    }
}

/// Which list a search belongs to. Pads and questions have distinct filter sets,
/// so the Suggested searches and the live-filter signatures are kept in separate
/// buckets even though they share the `NamedSearch` shape.
enum SavedSearchKind: String, Codable, Hashable {
    case pads
    case questions
}

/// The merged ("All Accounts") lists' persisted live-filter snapshot: the shared
/// `NamedSearch` body plus the merged-only account and preset filters it cannot
/// carry. Persisting only the `NamedSearch` subset silently broadened results on
/// the next launch whenever an account filter or a Mine/Favorites preset was
/// active (#913).
struct MergedFilterSnapshot: Codable {
    var search: NamedSearch
    var accountFilter: UUID?
    var mineOnly: Bool
    var favoritesOnly: Bool

    init(search: NamedSearch, accountFilter: UUID? = nil,
         mineOnly: Bool = false, favoritesOnly: Bool = false) {
        self.search = search
        self.accountFilter = accountFilter
        self.mineOnly = mineOnly
        self.favoritesOnly = favoritesOnly
    }

    /// Lenient decoding so a snapshot persisted before a field existed still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        search = try container.decode(NamedSearch.self, forKey: .search)
        accountFilter = try container.decodeIfPresent(UUID.self, forKey: .accountFilter)
        mineOnly = try container.decodeIfPresent(Bool.self, forKey: .mineOnly) ?? false
        favoritesOnly = try container.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? false
    }
}
