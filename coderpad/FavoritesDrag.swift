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

#if os(macOS)
    import AppKit
#endif
import FastList
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// In-process type for an internal favorite drag. Exported (not declared in
    /// Info.plist) since the drag never leaves the app — only the sidebar drop
    /// target reads it, so no other process needs to recognize the identifier.
    /// `nonisolated` so the `Transferable` representations (which build in a
    /// nonisolated context) can reference it.
    nonisolated static let coderpadFavorite = UTType(exportedAs: "com.coderpad.favorite", conformingTo: .data)

    /// In-process type for reordering a favorite *within* the sidebar (#299). Kept
    /// distinct from ``coderpadFavorite`` so a reorder drag (favorite row → favorite
    /// row) never triggers the add-a-favorite drop, and vice versa.
    nonisolated static let coderpadFavoriteReorder = UTType(exportedAs: "com.coderpad.favorite-reorder",
                                                            conformingTo: .data)
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

/// The iPad drag payload for a pad or question row: the internal ``FavoriteDrop`` JSON so the
/// row can be dropped on the sidebar Favorites to pin it (#297), plus the row's web URL so it
/// still drags out to Safari, Notes, or a Split View — the two payloads the single macOS
/// `NSPasteboardItem` carries (see `padPasteboardItem`), reunited for the SwiftUI drag path.
/// macOS builds its drag at the AppKit layer because the hosted row content is hit-transparent
/// there; on iPad the row content isn't, so a native `.draggable` carrying this grabs directly.
struct FavoriteDragPayload: Transferable {
    let drop: FavoriteDrop
    /// The row's web URL, for external drops. Rows without one aren't draggable (mirrored by
    /// `padPasteboardItem` returning `nil`), so this is always present.
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        // The favorite payload first so an in-app drop on the sidebar prefers it…
        DataRepresentation(exportedContentType: .coderpadFavorite) { payload in
            try JSONEncoder().encode(payload.drop)
        }
        // …while other apps still receive a plain link.
        ProxyRepresentation { $0.url }
    }
}

extension View {
    /// iPad: makes a pad or question row draggable onto the sidebar Favorites (and out to
    /// Safari/Notes/Split View), carrying the same ``FavoriteDrop`` the macOS pasteboard path
    /// builds. A no-op on macOS, where `FastList.onRowDrag` supplies the richer `NSPasteboardItem`
    /// instead (the hosted row content there is hit-transparent, so a SwiftUI `.draggable`
    /// wouldn't grab). `payload` is `nil` for a row that can't be favourited (no account or URL).
    @ViewBuilder
    func favoriteDraggable(_ payload: FavoriteDragPayload?, title: String) -> some View {
        #if os(iOS)
            if let payload {
                // An explicit compact preview so the lift is a small chip rather than a
                // full-width snapshot of the row (matching FastList's URL-drag chip).
                draggable(payload) { FavoriteDragChip(title: title) }
            } else {
                self
            }
        #else
            self
        #endif
    }

    /// iPad: attaches a pad/question row's context menu with an explicit compact preview, so a
    /// long-press lifts a small title-and-star chip rather than a full-width snapshot of the row.
    ///
    /// `FastList`'s own `.rowContextMenu` only supplies a compact preview when a drag *URL* is
    /// configured (see `onRowDragURL`); these rows carry the richer ``FavoriteDragPayload`` via
    /// `.favoriteDraggable` instead of a URL, so `FastList` has no title to build a chip from and
    /// its long-press platter defaults to the whole row — full-width and padded with empty space
    /// under the row's `containerRelativeFrame` layout. Rendering the same ``MenuItem``s here (so
    /// the menu itself is unchanged) with an explicit preview keeps the platter compact. A no-op
    /// on macOS, where `FastList`'s AppKit `NSMenu` path drives the menu over hit-transparent
    /// content and this modifier's iOS `.rowContextMenu` stays gated off.
    @ViewBuilder
    func favoriteRowContextMenu(_ items: [MenuItem], title: String) -> some View {
        #if os(iOS)
            contextMenu {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    switch item {
                    case let .button(buttonTitle, isEnabled, role, action):
                        Button(role: role == .destructive ? .destructive : nil, action: action) {
                            Text(buttonTitle)
                        }
                        .disabled(!isEnabled)

                    case .separator:
                        Divider()
                    }
                }
            } preview: {
                FavoriteDragChip(title: title)
            }
        #else
            self
        #endif
    }
}

#if os(iOS)
    /// The compact lift preview for an iPad favourite drag: the row's title beside a star,
    /// sized to its content so the row lifts as a small chip instead of a full-width snapshot.
    private struct FavoriteDragChip: View {
        let title: String

        var body: some View {
            Label(title, systemImage: "star")
                .lineLimit(1)
                .font(.body)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                .fixedSize()
        }
    }
#endif

/// App-level signal that a favorite-able pad or question is currently being dragged,
/// so the sidebar can reveal its empty-Favourites drop zone *only* while a drop is
/// possible and keep no resting gap otherwise (#444). The NSTableView row drag has
/// clean begin/end callbacks, so `FastList` sets this true when such a drag begins
/// and false when it ends — no timeout or `NSDraggingSession` observer needed.
@MainActor @Observable
final class FavoriteDragMonitor {
    static let shared = FavoriteDragMonitor()
    private init() {}

    /// True while a pad/question carrying a `coderpadFavorite` payload is in flight.
    var isDragging = false
}

#if os(macOS)
    /// The favorite-drag lifecycle hooks the list columns share, passed into the
    /// design-system ``FastList``'s injected drag callbacks (#515). Keeping the
    /// favorite-payload inspection here means the reusable table never references the
    /// app's `coderpadFavorite` type or `FavoriteDragMonitor`. While a row carrying a
    /// favorite payload is dragged, reveal the sidebar's empty-state drop zone (#444).
    ///
    /// iOS: these hooks plug into the AppKit `NSTableView`-backed `FastList`, which has
    /// no iOS counterpart, so the whole lifecycle is macOS-only.
    @MainActor
    enum FavoriteDragLifecycle {
        /// A row drag began: reveal the drop zone only when the session actually carries a
        /// favorite payload, so a plain link-out drag doesn't reveal a target nothing can
        /// drop on.
        static let onBegan: (NSDraggingSession) -> Void = { session in
            let canFavorite = session.draggingPasteboard
                .canReadItem(withDataConformingToTypes: [UTType.coderpadFavorite.identifier])
            if canFavorite { FavoriteDragMonitor.shared.isDragging = true }
        }

        /// The drag dropped or was cancelled: collapse the revealed drop zone again.
        static let onEnded: () -> Void = { FavoriteDragMonitor.shared.isDragging = false }
    }
#endif

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
