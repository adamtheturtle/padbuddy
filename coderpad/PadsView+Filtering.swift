//
//  PadsView+Filtering.swift
//  coderpad
//
//  Split from PadsView+Sidebar.swift to keep it within the lint length limit:
//  the memoized filter pipeline and filter-reset helpers moved here.
//

import SwiftUI

extension PadsView {
    static let dateRangeOptions = PadDateRange.options

    /// The filtered list, memoized for the duration of one render. `filtered` is
    /// read several times per `body` evaluation (the list, the result count, the
    /// empty state, and the bulk-action menu), and re-running the full O(n) filter
    /// on each read beach-balled large pad lists the moment a filter changed.
    /// `refreshFiltered()` recomputes it once at the top of `body`, so every read in
    /// that pass is O(1) and always current.
    var filtered: [Pad] {
        filteredCache.pads
    }

    func refreshFiltered() {
        // Skip the filter+sort when nothing that affects the result changed. `body`
        // re-runs several times per click as the selection settles, and only the
        // selection differs across those passes — re-filtering and re-sorting the
        // whole org each time is what made clicking a row slow on large lists (#395).
        let key = FilteredPadsCache.Key(
            padsRevision: padsRevision,
            filterSignature: filterSignature,
            sortRawValue: sort.rawValue,
            directoryCount: directory.nameByEmail.count
        )
        guard filteredCache.key != key else { return }

        let matched = PadListLogic.filter(
            pads,
            using: PadFilterCriteria(
                search: search,
                state: stateFilter,
                language: languageFilter,
                owner: ownerFilter,
                team: teamFilter,
                type: typeFilter,
                updated: updatedWindow,
                created: createdWindow
            ),
            display: directory.display
        )
        filteredCache.pads = sort.sorted(matched)
        filteredCache.key = key
    }

    /// The pad to select after the pad with `id` is deleted. Picks the row that
    /// takes the deleted row's position (the next one down), falling back to the
    /// previous pad when the deleted pad was last, and to `nil` when it was the
    /// only visible pad. Resolved against `filtered` — the list the user actually
    /// sees — so a hidden pad never becomes the new selection.
    func neighborSelection(forDeleted id: String) -> Pad? {
        let visible = filtered
        // If the deleted pad isn't in the visible list (e.g. filters changed after it
        // was selected), fall back to the first visible pad rather than blanking the
        // detail pane when there are still pads to show.
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.first }

        if visible.indices.contains(index + 1) { return visible[index + 1] }
        if visible.indices.contains(index - 1) { return visible[index - 1] }
        return nil
    }

    /// Resets every live filter. Shared by the toolbar Clear button and the
    /// filtered empty state so the two never drift.
    func clearAllFilters() {
        stateFilter = nil; languageFilter = nil
        ownerFilter = nil; teamFilter = nil; typeFilter = nil
        updatedWindow = DateWindow(); createdWindow = DateWindow()
    }
}
