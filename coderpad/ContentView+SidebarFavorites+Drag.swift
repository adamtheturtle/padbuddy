//
//  ContentView+SidebarFavorites+Drag.swift
//  coderpad
//
//  The drag-and-drop plumbing behind the sidebar Favorites section: decoding dropped
//  pads/questions, pinning them at the released position, dragging a favourite to
//  reorder it, and the per-row/section drop chrome. Split out of
//  ContentView+SidebarFavorites.swift to keep each file within its length budget; the
//  rendering half (the rows and their titles) stays there.
//

import SwiftUI
import UniformTypeIdentifiers

extension Sidebar {
    /// Decodes a dragged-in `FavoriteDrop` from a provider and hands it to `perform`
    /// on the main actor. Shared by the section container (which appends) and each
    /// favorite row's drop target (which inserts at the dropped position).
    func loadFavoriteDrop(from provider: NSItemProvider, perform: @escaping @MainActor (FavoriteDrop) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.coderpadFavorite.identifier) { data, _ in
            guard let data, let drop = try? JSONDecoder().decode(FavoriteDrop.self, from: data) else { return }

            Task { @MainActor in perform(drop) }
        }
    }

    /// Pins a dropped pad or question immediately before `item` in the combined order, so
    /// a drop lands where it was released rather than at the end. The item is added to its
    /// kind's store, then the shared order places it before the target — across kinds now,
    /// so a question can land between two pads and vice versa. A drop from a different
    /// account than the row's still pins (to its own account), just without the
    /// before-positioning, since order is per-account.
    func addDroppedFavorite(_ drop: FavoriteDrop, before item: FavoriteEntry) {
        let dropped: FavoriteRef
        let account: UUID
        switch drop {
        case let .pad(dropAccount, id, title):
            favoritePads.add(id, title: title, account: dropAccount)
            dropped = .pad(id)
            account = dropAccount
        case let .question(dropAccount, id, title):
            favorites.add(id, title: title, account: dropAccount)
            dropped = .question(id)
            account = dropAccount
        }
        if isMergedView, let targetAccount = item.account {
            favoritesOrder.moveMerged(
                MergedFavoriteRef(account: account, ref: dropped),
                before: MergedFavoriteRef(account: targetAccount, ref: item.ref),
                present: presentMergedRefs()
            )
            return
        }

        guard let target = item.account ?? accountID, target == account else { return }

        favoritesOrder.move(dropped, before: item.ref, present: presentRefs(account: account), account: account)
    }

    /// Decodes a within-sidebar `FavoriteReorder` from a provider and applies the move.
    func loadFavoriteReorder(
        from provider: NSItemProvider,
        onReorder: @escaping @MainActor (FavoriteReorder) -> Void
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.coderpadFavoriteReorder.identifier) { data, _ in
            guard let data, let reorder = try? JSONDecoder().decode(FavoriteReorder.self, from: data) else { return }

            Task { @MainActor in onReorder(reorder) }
        }
    }

    func removeFavoriteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label("Remove from Favorites", systemImage: "star.slash")
        }
    }

    /// Pins each dropped pad or question to the account carried in its payload (the
    /// originating account, so a drop in the combined view lands on the right one).
    /// Returns whether anything was accepted, which drives the drop animation.
    func handleFavoriteDrop(_ drops: [FavoriteDrop]) -> Bool {
        var accepted = false
        for drop in drops {
            switch drop {
            case let .pad(account, id, title):
                favoritePads.add(id, title: title, account: account)
                accepted = true

            case let .question(account, id, title):
                favorites.add(id, title: title, account: account)
                accepted = true
            }
        }
        return accepted
    }

    /// Wraps a favorite row so it can be dragged to reorder (#299): it carries a
    /// `FavoriteReorder` payload, draws a Finder-style insertion line above itself
    /// while a drag hovers, and reorders on drop. The row's own drop target accepts
    /// both a within-sidebar reorder *and* an add-a-favorite drag from a list — without
    /// the latter, the row would occlude the section's add target and leave each row a
    /// dead spot where a question or pad couldn't be dropped (#346).
    @ViewBuilder
    func favoriteRowChrome(
        rowID: String,
        payload: FavoriteReorder?,
        onReorder: @escaping @MainActor (FavoriteReorder) -> Void,
        onAdd: @escaping @MainActor (FavoriteDrop) -> Void,
        @ViewBuilder row: () -> some View
    ) -> some View {
        let decorated = row()
            .overlay(alignment: .top) {
                if reorderTargetID == rowID {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
            }
            // `.onDrop` rather than `.dropDestination(for:)` for the same reason as the
            // section target: the latter never fires its action inside a `List` row.
            .onDrop(of: [.coderpadFavoriteReorder, .coderpadFavorite], isTargeted: Binding(
                get: { reorderTargetID == rowID },
                set: { targeted in
                    reorderTargetID = targeted ? rowID : (reorderTargetID == rowID ? nil : reorderTargetID)
                }
            )) { providers in
                for provider in providers {
                    if provider.hasItemConformingToTypeIdentifier(UTType.coderpadFavoriteReorder.identifier) {
                        loadFavoriteReorder(from: provider) { reorder in
                            reorderTargetID = nil
                            onReorder(reorder)
                        }
                    } else {
                        loadFavoriteDrop(from: provider, perform: onAdd)
                    }
                }
                return true
            }
        // Only rows whose owning account is known can be dragged to reorder.
        if let payload {
            decorated.draggable(payload)
        } else {
            decorated
        }
    }

    func reorderPayload(_ item: FavoriteEntry) -> FavoriteReorder? {
        guard let account = item.account ?? accountID else { return nil }

        switch item.ref {
        case let .pad(id): return .pad(account: account, id: id)
        case let .question(id): return .question(account: account, id: id)
        }
    }

    /// Reorders a dragged favourite to sit before `item` in the shared order, but only
    /// within the same account (a reorder never moves a favourite between accounts). The
    /// dragged item and the target can be different kinds, so a question can be dropped
    /// between two pads and vice versa.
    func reorder(_ dropped: FavoriteReorder, before item: FavoriteEntry) {
        guard let resolved = favoriteReorderRef(dropped) else { return }

        if isMergedView, let targetAccount = item.account {
            favoritesOrder.moveMerged(
                MergedFavoriteRef(account: resolved.account, ref: resolved.ref),
                before: MergedFavoriteRef(account: targetAccount, ref: item.ref),
                present: presentMergedRefs()
            )
            return
        }

        guard let targetAccount = item.account ?? accountID, resolved.account == targetAccount else { return }

        favoritesOrder.move(resolved.ref, before: item.ref,
                            present: presentRefs(account: resolved.account), account: resolved.account)
    }

    /// Reorders a dragged favourite to the bottom of the visible shared order. In merged
    /// mode that means the bottom of the cross-account list; otherwise it means the bottom
    /// of the current account's favourites.
    func moveFavoriteToEnd(_ dropped: FavoriteReorder) {
        guard let resolved = favoriteReorderRef(dropped) else { return }

        if isMergedView {
            favoritesOrder.moveMergedToEnd(
                MergedFavoriteRef(account: resolved.account, ref: resolved.ref),
                present: presentMergedRefs()
            )
            return
        }

        favoritesOrder.moveToEnd(resolved.ref,
                                 present: presentRefs(account: resolved.account), account: resolved.account)
    }

    private func favoriteReorderRef(_ dropped: FavoriteReorder) -> (ref: FavoriteRef, account: UUID)? {
        switch dropped {
        case let .pad(account, id): return (.pad(id), account)
        case let .question(account, id): return (.question(id), account)
        }
    }
}

/// Shared chrome for a favourites drop target: fills the section's full width and makes
/// the whole rectangle — including the gaps between rows and the empty space below them —
/// one hit-testable region, and paints the Finder-style highlight while a drag hovers, so
/// a drop lands anywhere over the section rather than only on a row's exact bounds (#346).
struct FavoriteDropChrome: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
    }
}
