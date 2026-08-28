//
//  FavoriteQuestion.swift
//  coderpad
//
//  One starred question: its id, the title captured when it was starred, and when.
//

import Foundation
import os
import SwiftUI

/// One starred question: its per-org id plus the title captured when it was
/// favorited. Persisting the title lets the sidebar show the question's name
/// immediately — even before the questions list has loaded — instead of a
/// "Question #id" placeholder (#325).
struct FavoriteQuestion: Codable, Hashable {
    let id: Int
    var title: String
    /// When this favorite was (re-)starred, so a deletion tombstone from another
    /// device can be ordered against it (#738). Optional so entries persisted
    /// before it existed still decode; they count as arbitrarily old.
    var addedAt: Date?
}
