//
//  ContentView+SidebarFavorites.swift
//  coderpad
//

import SwiftUI
import UniformTypeIdentifiers

extension Sidebar {
    // MARK: Favorites

    /// One favourite row, pad or question, in the shared drag-ordered list. The kind and
    /// the kind's own id travel in `ref`; the rest is what the row needs to render and route.
    private struct FavoriteEntry: Identifiable {
        /// Unique per row. Pad ids and question ids can't be told apart by value alone (a
        /// slug vs an Int), and in the merged view two accounts can both favourite the same
        /// id, so the row id carries the kind and (in the merged view) the account.
        let id: String
        let ref: FavoriteRef
        /// The owning account when shown in the merged view, so a tap selects the right
        /// account's row and a reorder stays scoped to it; `nil` in a single-account view.
        let account: UUID?
        let title: String
    }

    /// The account's favourites in the default pads-then-questions order — the seed the
    /// shared order store reconciles its saved drag order against (see ``FavoritesOrderStore``).
    private func presentRefs(account: UUID) -> [FavoriteRef] {
        favoritePads.favorites(account: account).map { FavoriteRef.pad($0) }
            + favorites.favorites(account: account).map { FavoriteRef.question($0) }
    }

    /// The favourites to show, pads and starred questions interleaved in one drag order
    /// (see ``FavoritesOrderStore``): the current account's in a single-account view, or
    /// every mergeable account's (in account order) in the combined "All Accounts" view,
    /// so favourites stay reachable from the sidebar there too. Each account keeps its own
    /// order, so the combined view still groups by account even though within an account
    /// the two kinds interleave freely.
    private var favoriteEntries: [FavoriteEntry] {
        if isMergedView {
            return accounts.mergeableAccounts.flatMap { favoriteEntries(forAccount: $0.id, namespaced: true) }
        }
        guard let account = accountID else { return [] }

        return favoriteEntries(forAccount: account, namespaced: false)
    }

    /// Builds one account's favourite rows in their saved drag order. Pad titles come from
    /// the pads cache (falling back to the id); question titles come from the live
    /// questions cache when present (so renames show through), else the title stored with
    /// the favourite — so the name shows even before the list loads (#325), with
    /// "Question #id" only a last resort for a legacy favourite not yet seen.
    private func favoriteEntries(forAccount account: UUID, namespaced: Bool) -> [FavoriteEntry] {
        let questions = favorites.titledFavorites(account: account)
        guard !favoritePads.favorites(account: account).isEmpty || !questions.isEmpty else { return [] }

        let ordered = favoritesOrder.order(present: presentRefs(account: account), account: account)
        let padTitles = Dictionary(
            padsCache.get(account).map { ($0.id, $0.title.isEmpty ? $0.id : $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        let cacheTitles = Dictionary(
            questionsCache.get(account).map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        let storedTitles = Dictionary(
            questions.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        return ordered.map { ref in
            switch ref {
            case let .pad(padID):
                return FavoriteEntry(
                    id: namespaced ? "\(account.uuidString)-pad-\(padID)" : "pad-\(padID)",
                    ref: ref,
                    account: namespaced ? account : nil,
                    title: padTitles[padID] ?? padID
                )
            case let .question(questionID):
                let stored = storedTitles[questionID] ?? ""
                let resolved = cacheTitles[questionID]
                    ?? (stored.isEmpty ? "Question #\(questionID)" : stored)
                return FavoriteEntry(
                    id: namespaced ? "\(account.uuidString)-q-\(questionID)" : "q-\(questionID)",
                    ref: ref,
                    account: namespaced ? account : nil,
                    title: resolved
                )
            }
        }
    }

    /// Favourite pads and starred questions share one headed "Favorites" section as a
    /// single drag-ordered list (#571): each row carries its own kind glyph (a pad/document
    /// vs a question bubble) instead of a tinted star, so the kind stays legible without
    /// splitting the list, and the two kinds interleave freely in whatever order they were
    /// dragged into — nothing groups pads above questions. The section hides when there's
    /// nothing favourited and nothing being dragged (#440/#444): an empty `List` row still
    /// reserves a minimum height, so gating the whole section keeps no resting gap.
    @ViewBuilder
    var favoritesSection: some View {
        let entries = favoriteEntries
        if !entries.isEmpty || favoriteDragMonitor.isDragging {
            Section("Favorites") {
                favoritesBody(entries).sidebarGroupRow()
            }
        }
    }

    /// The favourite rows, their empty-state drop hint, the drag-to-reorder insertion
    /// line, and the drop-to-pin target. Kept as one `List` row so the whole interaction
    /// works inside the rebuilt list sidebar (#281/#288, #346).
    private func favoritesBody(_ entries: [FavoriteEntry]) -> some View {
        // Capture the stores/binding (not `self`) in the per-row tap and delete closures
        // — see the note in `Sidebar.defaultsSection`: capturing the whole `Sidebar`
        // struct faults in `swift_retain` while SwiftUI copies the row value on the iPad
        // layout path (a black-screen crash on first layout).
        let nav = nav
        let favoritePads = favoritePads
        let favorites = favorites
        let accountID = accountID
        let sectionBinding = $section
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(entries) { item in
                favoriteRowChrome(
                    rowID: item.id,
                    payload: reorderPayload(item),
                    onReorder: { reorder($0, before: item) },
                    onAdd: { addDroppedFavorite($0, before: item) },
                    row: {
                        favoriteRow(item, deps: FavoriteRowDeps(
                            nav: nav,
                            favoritePads: favoritePads,
                            favorites: favorites,
                            accountID: accountID,
                            sectionBinding: sectionBinding
                        ))
                    }
                )
            }
            if entries.isEmpty { favoriteDropSpacer }
        }
        .modifier(FavoriteDropChrome(isHighlighted: droppingFavorites))
        .onDrop(of: [.coderpadFavorite], isTargeted: $droppingFavorites) { providers in
            for provider in providers {
                loadFavoriteDrop(from: provider) { _ = handleFavoriteDrop([$0]) }
            }
            return true
        }
    }

    /// One favourite row: a pad opens its pad, a question opens its question, each with the
    /// same glyph its own section uses (a document vs a question bubble) so the kind reads
    /// at a glance without a tinted star (#571). In the merged view the tap routes through
    /// `MergedRouting` so the right account's row is selected (per-org ids collide, so the
    /// account must travel with the id).
    /// The stores and bindings a favourite row acts on, bundled so the row builder
    /// stays under the parameter-count limit while still receiving them as locals —
    /// never read from `self`, whose capture in a sidebar action closure crashed on
    /// iPad (see the sidebar self-capture fix).
    struct FavoriteRowDeps {
        let nav: AppNavigation
        let favoritePads: FavoritePadsStore
        let favorites: FavoriteQuestionsStore
        let accountID: UUID?
        let sectionBinding: Binding<AppSection>
    }

    @ViewBuilder
    private func favoriteRow(_ item: FavoriteEntry, deps: FavoriteRowDeps) -> some View {
        let nav = deps.nav
        let favoritePads = deps.favoritePads
        let favorites = deps.favorites
        let accountID = deps.accountID
        let sectionBinding = deps.sectionBinding
        switch item.ref {
        case let .pad(padID):
            sidebarSubRow(label: item.title, icon: "doc.text") {
                if item.account != nil {
                    sectionBinding.wrappedValue = .pads
                    MergedRouting.shared.selectFavoritePad(id: padID)
                } else {
                    nav.showFavoritePad(id: padID)
                }
            }
            .contextMenu {
                removeFavoriteButton {
                    if let account = item.account ?? accountID {
                        favoritePads.remove(padID, account: account)
                    }
                }
            }
        case let .question(questionID):
            sidebarSubRow(label: item.title, icon: "questionmark.bubble") {
                if let account = item.account {
                    sectionBinding.wrappedValue = .questions
                    MergedRouting.shared.selectFavoriteQuestion(account: account, id: questionID)
                } else {
                    nav.showFavoriteQuestion(id: questionID)
                }
            }
            .contextMenu {
                removeFavoriteButton {
                    if let account = item.account ?? accountID {
                        favorites.toggle(questionID, title: item.title, account: account)
                    }
                }
            }
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
            .animation(reduceMotion ? nil : .smooth, value: favoriteDragMonitor.isDragging)
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

    /// Pins a dropped pad or question immediately before `item` in the combined order, so
    /// a drop lands where it was released rather than at the end. The item is added to its
    /// kind's store, then the shared order places it before the target — across kinds now,
    /// so a question can land between two pads and vice versa. A drop from a different
    /// account than the row's still pins (to its own account), just without the
    /// before-positioning, since order is per-account.
    private func addDroppedFavorite(_ drop: FavoriteDrop, before item: FavoriteEntry) {
        let dropped: FavoriteRef
        let account: UUID
        switch drop {
        case let .pad(dropAccount, id, _):
            favoritePads.add(id, account: dropAccount)
            dropped = .pad(id)
            account = dropAccount
        case let .question(dropAccount, id, title):
            favorites.add(id, title: title, account: dropAccount)
            dropped = .question(id)
            account = dropAccount
        }
        guard let target = item.account ?? accountID, target == account else { return }

        favoritesOrder.move(dropped, before: item.ref, present: presentRefs(account: account), account: account)
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

    private func reorderPayload(_ item: FavoriteEntry) -> FavoriteReorder? {
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
    private func reorder(_ dropped: FavoriteReorder, before item: FavoriteEntry) {
        guard let targetAccount = item.account ?? accountID else { return }

        let ref: FavoriteRef
        let account: UUID
        switch dropped {
        case let .pad(dropAccount, id): ref = .pad(id); account = dropAccount
        case let .question(dropAccount, id): ref = .question(id); account = dropAccount
        }
        guard account == targetAccount else { return }

        favoritesOrder.move(ref, before: item.ref, present: presentRefs(account: account), account: account)
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
