//
//  PadsView+Caches.swift
//  coderpad
//
//  Per-render memo helpers for PadsView: the task restart key and the filtered-list
//  and chip-option caches that let body's several reads share a single pass.
//

import SwiftUI

/// Restart key for the per-session load task: the account's API key plus the scene
/// endpoint and scene phase, so the task re-runs when any of them changes.
struct PadsTaskKey: Hashable {
    let apiKey: String
    let baseURL: URL
    let phase: ScenePhase
}

/// Holds the filtered pad list across one render so the several reads of `filtered`
/// in `PadsView.body` share a single filter pass. A class (not a `@State` value) so
/// `body` can refresh it without triggering a SwiftUI state mutation.
final class FilteredPadsCache {
    var pads: [Pad] = []
    /// The inputs `pads` was last computed for. When an unrelated body pass (e.g. a
    /// selection change) leaves these identical, `refreshFiltered()` reuses the same
    /// array instead of re-filtering and re-sorting the whole org (#395).
    var key: Key?

    struct Key: Equatable {
        let padsRevision: Int
        let filterSignature: FilterSignature
        let sortRawValue: String
        /// Rolling date filters depend on the current clock, not just the selected
        /// range, so active date windows add a time bucket to the cache key.
        let dateFilterTimeToken: String?
        /// Owner display names feed the search predicate, so a directory that finishes
        /// loading after the list must re-filter. Its revision tracks content, not
        /// just count: a same-size reload with renamed members must re-filter too (#1198).
        let directoryRevision: Int
    }
}

/// Holds the filter-chip option lists (states, languages, owners, teams) across one
/// render so the filter bar's reads share a single pass over `pads`. Each list is a
/// Set build + sort over the whole pad array, and the bar is rendered in `body`, so
/// without this each was an O(n) scan re-run on every selection-driven body pass —
/// the same selection-lag profile #395 fixed for the list (#416). A class so `body`
/// can refresh it without mutating SwiftUI state mid-evaluation; the cross-account
/// `MergedPadsView` already memoizes these the same way (`scopedCache`).
final class PadChipOptionsCache {
    var states: [PadState] = []
    var languages: [String] = []
    var owners: [String] = []
    var teams: [String] = []
    var teamCounts: [String: Int] = [:]
    /// The inputs these were computed for, so an unrelated body pass (a selection
    /// change) reuses them.
    var key: Key?

    struct Key: Equatable {
        let padsRevision: Int
        /// Owners are ordered by their resolved display names, so a directory load or
        /// a rename changes the right order without touching the pads (#2487).
        let directoryRevision: Int
    }
}
