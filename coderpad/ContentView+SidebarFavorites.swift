//
//  ContentView+SidebarFavorites.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

extension Sidebar {
    // MARK: Favorites

    private struct FavoriteItem: Identifiable {
        /// Unique per row. In the merged view two accounts can both star a question
        /// with the same per-org id, so the row id namespaces by account.
        let id: String
        let questionID: Int
        /// The owning account when shown in the merged view, so a tap selects the
        /// right account's row; `nil` in a single-account view.
        let account: UUID?
        let title: String
    }

    private struct FavoritePadItem: Identifiable {
        /// Unique per row. Pad ids are globally unique, but the merged view still
        /// namespaces by account so removing a favorite targets the right account.
        let id: String
        let padID: String
        /// The owning account when shown in the merged view; `nil` single-account.
        let account: UUID?
        let title: String
    }

    /// The pinned pads to show, mirroring `favoriteItems` for questions: the current
    /// account's in a single-account view, or every mergeable account's in the
    /// combined view. Titles come from each account's pads cache, falling back to the id.
    private var favoritePadItems: [FavoritePadItem] {
        if isMergedView {
            return accounts.mergeableAccounts.flatMap { favoritePadItems(forAccount: $0.id, namespaced: true) }
        }
        guard let account = accountID else { return [] }

        return favoritePadItems(forAccount: account, namespaced: false)
    }

    private func favoritePadItems(forAccount account: UUID, namespaced: Bool) -> [FavoritePadItem] {
        let ids = favoritePads.favorites(account: account)
        guard !ids.isEmpty else { return [] }

        let titles = Dictionary(
            padsCache.get(account).map { ($0.id, $0.title.isEmpty ? $0.id : $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        return ids.map { id in
            FavoritePadItem(
                id: namespaced ? "\(account.uuidString)-\(id)" : id,
                padID: id,
                account: namespaced ? account : nil,
                title: titles[id] ?? id
            )
        }
    }

    /// The starred questions to show: the current account's in a single-account view,
    /// or every mergeable account's (in account order) in the combined "All Accounts"
    /// view, so favorites stay reachable from the sidebar there too. The title comes
    /// from the live questions cache when present (so renames show through), else the
    /// title stored with the favorite — so the name shows even before the list loads
    /// (#325), and "Question #id" is only ever a last resort for a legacy favorite
    /// whose question hasn't been seen yet.
    private var favoriteItems: [FavoriteItem] {
        if isMergedView {
            return accounts.mergeableAccounts.flatMap { favoriteItems(forAccount: $0.id, namespaced: true) }
        }
        guard let account = accountID else { return [] }

        return favoriteItems(forAccount: account, namespaced: false)
    }

    private func favoriteItems(forAccount account: UUID, namespaced: Bool) -> [FavoriteItem] {
        let favorites = favorites.titledFavorites(account: account)
        guard !favorites.isEmpty else { return [] }

        let cacheTitles = Dictionary(
            questionsCache.get(account).map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        return favorites.map { favorite in
            let resolved = cacheTitles[favorite.id]
                ?? (favorite.title.isEmpty ? "Question #\(favorite.id)" : favorite.title)
            return FavoriteItem(
                id: namespaced ? "\(account.uuidString)-\(favorite.id)" : "\(favorite.id)",
                questionID: favorite.id,
                account: namespaced ? account : nil,
                title: resolved
            )
        }
    }

    /// Favourite pads and questions share one headed "Favorites" section (#571): pads
    /// list first, then questions, each row carrying its own kind glyph (a pad/document
    /// vs a question bubble) instead of a single yellow star, so the kind is legible
    /// without splitting the sidebar into two headers. Each kind's rows still render
    /// only when that kind has favourites or a drag is in progress, so the section never
    /// shows an empty pad or question group at rest; the whole section hides when neither
    /// kind has anything and nothing is being dragged (#440/#444) — an empty `List` row
    /// still reserves a minimum height, so gating each body keeps no resting gap. Each
    /// body keeps its own drop zone, so a row dragged onto either kind pins to the
    /// account it came from (carried in the payload), landing on the right account in
    /// the combined view.
    @ViewBuilder
    var favoritesSection: some View {
        if !favoritePadItems.isEmpty || !favoriteItems.isEmpty || favoriteDragMonitor.isDragging {
            Section("Favorites") {
                if !favoritePadItems.isEmpty || favoriteDragMonitor.isDragging {
                    favoritePadsBody(favoritePadItems).sidebarGroupRow()
                }
                if !favoriteItems.isEmpty || favoriteDragMonitor.isDragging {
                    favoriteQuestionsBody(favoriteItems).sidebarGroupRow()
                }
            }
        }
    }

    /// The pinned-pad rows, their empty-state hint, the drag-to-reorder insertion line,
    /// and the drop-to-pin target. Kept as one `List` row so the whole interaction works
    /// inside the rebuilt list sidebar (#281/#288, #346).
    private func favoritePadsBody(_ pads: [FavoritePadItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(pads) { item in
                favoriteRowChrome(
                    rowID: item.id,
                    payload: padReorderPayload(item),
                    onReorder: { reorderPad($0, before: item) },
                    onAdd: { addDroppedFavorite($0, beforePad: item) },
                    row: {
                        // A document glyph marks the favourite as a pad — the same icon
                        // the Pads section uses — so pads and questions read apart in the
                        // combined Favorites section without a tinted star (#571).
                        sidebarSubRow(label: item.title, icon: "doc.text") {
                            if item.account != nil {
                                section = .pads
                                MergedRouting.shared.selectFavoritePad(id: item.padID)
                            } else {
                                nav.showFavoritePad(id: item.padID)
                            }
                        }
                        .contextMenu { removeFavoriteButton { unfavoritePad(item) } }
                    }
                )
            }
            if pads.isEmpty { favoriteDropSpacer }
        }
        .modifier(FavoriteDropChrome(isHighlighted: droppingFavoritePads))
        .onDrop(of: [.coderpadFavorite], isTargeted: $droppingFavoritePads) { providers in
            for provider in providers {
                loadFavoriteDrop(from: provider) { _ = handleFavoriteDrop([$0]) }
            }
            return true
        }
    }

    /// The starred-question rows, mirroring ``favoritePadsBody`` for the question store.
    private func favoriteQuestionsBody(_ questions: [FavoriteItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(questions) { item in
                favoriteRowChrome(
                    rowID: item.id,
                    payload: questionReorderPayload(item),
                    onReorder: { reorderQuestion($0, before: item) },
                    onAdd: { addDroppedFavorite($0, beforeQuestion: item) },
                    row: {
                        // A question-bubble glyph marks the favourite as a question — the
                        // same icon the Questions section uses — distinguishing it from a
                        // favourite pad in the shared Favorites section (#571).
                        sidebarSubRow(label: item.title, icon: "questionmark.bubble") {
                            if let account = item.account {
                                // Merged view: switch to the combined questions list and let
                                // it select the right account's row (per-org ids collide, so
                                // the account must travel with the id).
                                section = .questions
                                MergedRouting.shared.selectFavoriteQuestion(account: account, id: item.questionID)
                            } else {
                                nav.showFavoriteQuestion(id: item.questionID)
                            }
                        }
                        .contextMenu { removeFavoriteButton { unfavoriteQuestion(item) } }
                    }
                )
            }
            if questions.isEmpty { favoriteDropSpacer }
        }
        .modifier(FavoriteDropChrome(isHighlighted: droppingFavoriteQuestions))
        .onDrop(of: [.coderpadFavorite], isTargeted: $droppingFavoriteQuestions) { providers in
            for provider in providers {
                loadFavoriteDrop(from: provider) { _ = handleFavoriteDrop([$0]) }
            }
            return true
        }
    }

    /// An empty favourites section's drop zone, revealed *only* while a favorite drag is
    /// in flight (#444) so the section keeps no resting gap (the earlier always-present
    /// 28pt spacer from #440 read as unfinished). When a drag begins, it expands to give
    /// the section's `.onDrop` a non-zero target; on drop/cancel it collapses again. The
    /// `FavoriteDropChrome` highlight still signals droppability while a drag hovers.
    private var favoriteDropSpacer: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: favoriteDragMonitor.isDragging ? 28 : 0)
            .contentShape(Rectangle())
            .animation(.smooth, value: favoriteDragMonitor.isDragging)
    }

    /// Decodes a dragged-in `FavoriteDrop` from a provider and hands it to `perform`
    /// on the main actor. Shared by the section container (which appends) and each
    /// favorite row's drop target (which inserts at the dropped position).
    private func loadFavoriteDrop(from provider: NSItemProvider, perform: @escaping @MainActor (FavoriteDrop) -> Void) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.coderpadFavorite.identifier) { data, _ in
            guard let data, let drop = try? JSONDecoder().decode(FavoriteDrop.self, from: data) else { return }

            Task { @MainActor in perform(drop) }
        }
    }

    /// Pins a dropped pad immediately before `item` in the favourites' pad group, so a
    /// drop lands where it was released rather than at the end. A question dropped onto
    /// a pad row can't interleave among pads (the kinds are separate, ordered groups),
    /// so it appends to its own group instead.
    private func addDroppedFavorite(_ drop: FavoriteDrop, beforePad item: FavoritePadItem) {
        guard case let .pad(account, id, _) = drop else { _ = handleFavoriteDrop([drop]); return }

        favoritePads.add(id, account: account)
        if let target = item.account ?? accountID, target == account {
            favoritePads.move(id, before: item.padID, account: account)
        }
    }

    /// Pins a dropped question immediately before `item` in the favourites' question
    /// group. A pad dropped onto a question row appends to the pad group instead.
    private func addDroppedFavorite(_ drop: FavoriteDrop, beforeQuestion item: FavoriteItem) {
        guard case let .question(account, id, title) = drop else { _ = handleFavoriteDrop([drop]); return }

        favorites.add(id, title: title, account: account)
        if let target = item.account ?? accountID, target == account {
            favorites.move(id, before: item.questionID, account: account)
        }
    }

    /// Decodes a within-sidebar `FavoriteReorder` from a provider and applies the move.
    private func loadFavoriteReorder(
        from provider: NSItemProvider,
        onReorder: @escaping @MainActor (FavoriteReorder) -> Void
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.coderpadFavoriteReorder.identifier) { data, _ in
            guard let data, let reorder = try? JSONDecoder().decode(FavoriteReorder.self, from: data) else { return }

            Task { @MainActor in onReorder(reorder) }
        }
    }

    private func removeFavoriteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label("Remove from Favorites", systemImage: "star.slash")
        }
    }

    private func unfavoritePad(_ item: FavoritePadItem) {
        guard let account = item.account ?? accountID else { return }

        favoritePads.remove(item.padID, account: account)
    }

    private func unfavoriteQuestion(_ item: FavoriteItem) {
        guard let account = item.account ?? accountID else { return }

        favorites.toggle(item.questionID, title: item.title, account: account)
    }

    /// Pins each dropped pad or question to the account carried in its payload (the
    /// originating account, so a drop in the combined view lands on the right one).
    /// Returns whether anything was accepted, which drives the drop animation.
    private func handleFavoriteDrop(_ drops: [FavoriteDrop]) -> Bool {
        var accepted = false
        for drop in drops {
            switch drop {
            case let .pad(account, id, _):
                favoritePads.add(id, account: account)
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
    private func favoriteRowChrome(
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

    private func padReorderPayload(_ item: FavoritePadItem) -> FavoriteReorder? {
        guard let account = item.account ?? accountID else { return nil }

        return .pad(account: account, id: item.padID)
    }

    private func questionReorderPayload(_ item: FavoriteItem) -> FavoriteReorder? {
        guard let account = item.account ?? accountID else { return nil }

        return .question(account: account, id: item.questionID)
    }

    /// Reorders a dropped pad favorite to sit before `item`, but only within the
    /// same account (a reorder never moves a favorite between accounts).
    private func reorderPad(_ dropped: FavoriteReorder, before item: FavoritePadItem) {
        guard case let .pad(account, id) = dropped,
              let targetAccount = item.account ?? accountID,
              account == targetAccount else { return }

        favoritePads.move(id, before: item.padID, account: account)
    }

    private func reorderQuestion(_ dropped: FavoriteReorder, before item: FavoriteItem) {
        guard case let .question(account, id) = dropped,
              let targetAccount = item.account ?? accountID,
              account == targetAccount else { return }

        favorites.move(id, before: item.questionID, account: account)
    }
}

/// Shared chrome for a favourites drop target: fills the section's full width and makes
/// the whole rectangle — including the gaps between rows and the empty space below them —
/// one hit-testable region, and paints the Finder-style highlight while a drag hovers, so
/// a drop lands anywhere over the section rather than only on a row's exact bounds (#346).
private struct FavoriteDropChrome: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}
