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
        self.name = Self.clampedName(name)
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

    /// Enforces `maxNameLength`, which the type advertises but nothing applied.
    ///
    /// The text field in the rename sheet clamps as you type, but that was the only
    /// gate: a programmatic caller, a paste that bypassed it, or a persisted value
    /// from before the cap existed could all carry an arbitrarily long name into the
    /// model (#2555). Chips clamp their display, so the symptom was subtle — an
    /// oversized name still travelled through export, sync, and comparison.
    ///
    /// Truncation is by character, not UTF-8 length, so a name of emoji or
    /// combining marks is cut where a reader would expect.
    static func clampedName(_ name: String) -> String {
        name.count <= maxNameLength ? name : String(name.prefix(maxNameLength))
    }

    /// Decoding routes through the same clamp: a legacy or corrupt defaults entry
    /// otherwise reintroduced an oversized name the initializer would have refused
    /// (#2556).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try Self.clampedName(container.decode(String.self, forKey: .name))
        search = try container.decode(String.self, forKey: .search)
        stateFilter = try container.decodeIfPresent(PadState.self, forKey: .stateFilter)
        languageFilter = try container.decodeIfPresent(String.self, forKey: .languageFilter)
        ownerFilter = try container.decodeIfPresent(String.self, forKey: .ownerFilter)
        teamFilter = try container.decodeIfPresent(String.self, forKey: .teamFilter)
        typeFilter = try container.decodeIfPresent(String.self, forKey: .typeFilter)
        updatedWindow = try container.decodeIfPresent(DateWindow.self, forKey: .updatedWindow)
        createdWindow = try container.decodeIfPresent(DateWindow.self, forKey: .createdWindow)
        draftFilter = try container.decodeIfPresent(String.self, forKey: .draftFilter)
    }

    /// Whether two searches carry the same filter criteria, ignoring `id` and
    /// `name`. A live filter signature can be matched against a saved or built-in
    /// search regardless of how it was labeled, so the in-list chips and the
    /// sidebar share one definition of "this search is currently applied" and can
    /// never drift. Fields a given list doesn't use stay nil on both sides, so the
    /// full-field comparison is correct for both pads and questions.
    func hasSameFilters(as other: Self) -> Bool {
        Self.equivalent(search, other.search, trimmingWhitespace: true) &&
            stateFilter == other.stateFilter &&
            Self.equivalent(languageFilter, other.languageFilter, trimmingWhitespace: true) &&
            Self.equivalent(ownerFilter, other.ownerFilter) &&
            Self.equivalent(teamFilter, other.teamFilter) &&
            typeFilter == other.typeFilter &&
            updatedWindow == other.updatedWindow &&
            createdWindow == other.createdWindow &&
            draftFilter == other.draftFilter
    }

    private static func equivalent(
        _ lhs: String,
        _ rhs: String,
        trimmingWhitespace: Bool = false
    ) -> Bool {
        let left = trimmingWhitespace ? lhs.trimmingCharacters(in: .whitespacesAndNewlines) : lhs
        let right = trimmingWhitespace ? rhs.trimmingCharacters(in: .whitespacesAndNewlines) : rhs
        return left.localizedCaseInsensitiveCompare(right) == .orderedSame
    }

    private static func equivalent(
        _ lhs: String?,
        _ rhs: String?,
        trimmingWhitespace: Bool = false
    ) -> Bool {
        switch (lhs, rhs) {
        case let (left?, right?): equivalent(left, right, trimmingWhitespace: trimmingWhitespace)
        case (nil, nil): true
        default: false
        }
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
    /// The account filter's cross-device identity (`Account.syncID`), stored
    /// alongside the local `UUID`.
    ///
    /// `accountFilter` is a per-device random id, so a snapshot that reaches
    /// another Mac through preference sync — or survives a reinstall — names an
    /// account that no longer exists there. The filter was then dropped and the
    /// list silently widened to every account, which reads as the filter having
    /// stopped working (#2557). The sync id lines up across devices, so a restore
    /// can fall back to it. Optional: snapshots written before this existed, and
    /// draft accounts with no resolvable sync id, carry nil.
    var accountFilterSyncID: String?
    var mineOnly: Bool
    var favoritesOnly: Bool

    init(search: NamedSearch, accountFilter: UUID? = nil, accountFilterSyncID: String? = nil,
         mineOnly: Bool = false, favoritesOnly: Bool = false) {
        self.search = search
        self.accountFilter = accountFilter
        self.accountFilterSyncID = accountFilterSyncID
        (self.mineOnly, self.favoritesOnly) = Self.exclusivePresets(mineOnly: mineOnly,
                                                                    favoritesOnly: favoritesOnly)
    }

    /// Lenient decoding so a snapshot persisted before a field existed still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        search = try container.decode(NamedSearch.self, forKey: .search)
        accountFilter = try container.decodeIfPresent(UUID.self, forKey: .accountFilter)
        accountFilterSyncID = try container.decodeIfPresent(String.self, forKey: .accountFilterSyncID)
        (mineOnly, favoritesOnly) = try Self.exclusivePresets(
            mineOnly: container.decodeIfPresent(Bool.self, forKey: .mineOnly) ?? false,
            favoritesOnly: container.decodeIfPresent(Bool.self, forKey: .favoritesOnly) ?? false
        )
    }

    /// Enforces that at most one preset is on.
    ///
    /// The two are mutually exclusive in the UI — each toolbar toggle turns the
    /// other off — but they were decoded independently, so a snapshot corrupted or
    /// written by a build that let both be set restored a list constrained to
    /// "mine AND favorited", which is usually empty and offers no clue why (#2574).
    /// Favorites wins: it is the narrower, more deliberate pick, and it is the one
    /// whose toggle is visible in the merged questions bar.
    private static func exclusivePresets(mineOnly: Bool, favoritesOnly: Bool) -> (Bool, Bool) {
        favoritesOnly ? (false, true) : (mineOnly, false)
    }
}
