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
}
