//
//  FavoritesDrag.swift
//  coderpad
//
//  The drag-and-drop payloads behind "drag a pad or question onto the sidebar to
//  favorite it" (#297). A single internal `FavoriteDrop` type carries everything
//  the sidebar drop target needs to pin the right item to the right account, even
//  in the combined "All Accounts" view where the source account must travel with
//  the id. Pad rows keep dragging their web URL out for external drops (Slack,
//  Mail); since the #439 NSTableView migration that drag is assembled at the AppKit
//  layer (see `padPasteboardItem`), carrying the URL plus the `FavoriteDrop` JSON.
//

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// In-process type for an internal favorite drag. Exported (not declared in
    /// Info.plist) since the drag never leaves the app — only the sidebar drop
    /// target reads it, so no other process needs to recognize the identifier.
    /// `nonisolated` so the `Transferable` representations (which build in a
    /// nonisolated context) can reference it.
    nonisolated static let coderpadFavorite = UTType(exportedAs: "com.coderpad.favorite")

    /// In-process type for reordering a favorite *within* the sidebar (#299). Kept
    /// distinct from ``coderpadFavorite`` so a reorder drag (favorite row → favorite
    /// row) never triggers the add-a-favorite drop, and vice versa.
    nonisolated static let coderpadFavoriteReorder = UTType(exportedAs: "com.coderpad.favorite-reorder")
}

/// What a pad or question row hands the sidebar Favorites drop target. Codable so
/// it rides a `CodableRepresentation`; the account travels with the id so a drop in
/// the merged view pins to the originating account rather than the active one.
enum FavoriteDrop: Codable, Transferable {
    case pad(account: UUID, id: String, title: String)
    case question(account: UUID, id: Int, title: String)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .coderpadFavorite)
    }
}

/// App-level signal that a favorite-able pad or question is currently being dragged,
/// so the sidebar can reveal its empty-Favourites drop zone *only* while a drop is
/// possible and keep no resting gap otherwise (#444). The NSTableView row drag has
/// clean begin/end callbacks, so `ListTable` sets this true when such a drag begins
/// and false when it ends — no timeout or `NSDraggingSession` observer needed.
@MainActor @Observable
final class FavoriteDragMonitor {
    static let shared = FavoriteDragMonitor()
    private init() {}

    /// True while a pad/question carrying a `coderpadFavorite` payload is in flight.
    var isDragging = false
}

/// Identifies a favorite being dragged to reorder it within the sidebar (#299).
/// Separate from ``FavoriteDrop`` so reorder and add-to-favorites never cross-fire.
/// The account travels so reordering stays scoped to the right account's list.
enum FavoriteReorder: Codable, Transferable {
    case pad(account: UUID, id: String)
    case question(account: UUID, id: Int)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .coderpadFavoriteReorder)
    }
}
