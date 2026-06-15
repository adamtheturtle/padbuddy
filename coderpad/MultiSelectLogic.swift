//
//  MultiSelectLogic.swift
//  coderpad
//

import Foundation

/// Pure helpers for bridging a `List`'s multi-selection (`Set`) to the single
/// "primary" row that drives the detail pane. Kept free of SwiftUI so the rules
/// stay unit-testable in isolation, the way `PadsView.padToRestore` is.
enum MultiSelectLogic {
    /// The row whose detail to show after the selection set changes: prefer a
    /// newly added id (the row the user just clicked or ⌘-clicked), falling back to
    /// any id still in the set, and `nil` when nothing is selected. This keeps the
    /// detail pane following the last-touched row while several rows stay selected
    /// for a bulk action.
    static func primaryID<ID: Hashable>(previous: Set<ID>, current: Set<ID>) -> ID? {
        current.subtracting(previous).first ?? current.first
    }

    /// The new selection after a plain or ⌘-click on `id`. A plain click replaces
    /// the selection with just this row (the macOS default); ⌘-click toggles the
    /// row in or out of the current set, so several rows can be gathered for a
    /// bulk action. The rows drive selection explicitly through this because a tap
    /// gesture covering the whole row suppresses the list's own click-to-select on
    /// macOS (#324). ⇧-range selection isn't handled here — it stays available via
    /// the keyboard (⇧+arrow), which the list handles natively.
    static func clicked<ID: Hashable>(id: ID, in set: Set<ID>, command: Bool) -> Set<ID> {
        guard command else { return [id] }
        var next = set
        if next.contains(id) {
            next.remove(id)
        } else {
            next.insert(id)
        }
        return next
    }
}
