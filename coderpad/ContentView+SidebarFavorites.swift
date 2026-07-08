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
    struct FavoriteEntry: Identifiable {
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
    func presentRefs(account: UUID) -> [FavoriteRef] {
        favoritePads.favorites(account: account).map { FavoriteRef.pad($0) }
            + favorites.favorites(account: account).map { FavoriteRef.question($0) }
    }

    /// The favourites to show, pads and starred questions interleaved in one drag order
    /// (see ``FavoritesOrderStore``): the current account's in a single-account view, or
    /// every mergeable account's in one cross-account order in the combined "All Accounts"
    /// view, so favourites can be rearranged exactly where they appear.
    private var favoriteEntries: [FavoriteEntry] {
        if isMergedView {
            return favoritesOrder.merged(present: presentMergedRefs()).compactMap { item in
                favoriteEntry(forAccount: item.account, ref: item.ref, namespaced: true)
            }
        }
        guard let account = accountID else { return [] }

        return favoriteEntries(forAccount: account, namespaced: false)
    }

    func presentMergedRefs() -> [MergedFavoriteRef] {
        accounts.mergeableAccounts.flatMap { account in
            presentRefs(account: account.id).map { MergedFavoriteRef(account: account.id, ref: $0) }
        }
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
        return ordered.compactMap { favoriteEntry(forAccount: account, ref: $0, namespaced: namespaced) }
    }

    private func favoriteEntry(forAccount account: UUID, ref: FavoriteRef, namespaced: Bool) -> FavoriteEntry? {
        let questions = favorites.titledFavorites(account: account)
        let padTitles = Dictionary(
            padsCache.cached(account).compactMap { pad in pad.title.isEmpty ? nil : (pad.id, pad.title) },
            uniquingKeysWith: { first, _ in first }
        )
        let storedPadTitles = Dictionary(
            favoritePads.titledFavorites(account: account).map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        let cacheTitles = Dictionary(
            questionsCache.cached(account).map { ($0.id, $0.displayTitle) },
            uniquingKeysWith: { first, _ in first }
        )
        let storedTitles = Dictionary(
            questions.map { ($0.id, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        switch ref {
        case let .pad(padID):
            guard favoritePads.favorites(account: account).contains(padID) else { return nil }

            // Prefer the live cache title (so renames show through), then the title
            // captured when the pad was pinned (#654), and only fall back to the bare
            // slug for a legacy favourite whose pad hasn't loaded yet.
            let storedPad = storedPadTitles[padID] ?? ""
            return FavoriteEntry(
                id: namespaced ? "\(account.uuidString)-pad-\(padID)" : "pad-\(padID)",
                ref: ref,
                account: namespaced ? account : nil,
                title: padTitles[padID] ?? (storedPad.isEmpty ? padID : storedPad)
            )
        case let .question(questionID):
            guard favorites.favorites(account: account).contains(questionID) else { return nil }

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
        .onDrop(of: [.coderpadFavoriteReorder, .coderpadFavorite], isTargeted: $droppingFavorites) { providers in
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.coderpadFavoriteReorder.identifier) {
                    loadFavoriteReorder(from: provider) { reorder in
                        reorderTargetID = nil
                        moveFavoriteToEnd(reorder)
                    }
                } else {
                    loadFavoriteDrop(from: provider) { _ = handleFavoriteDrop([$0]) }
                }
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
                        favoritePads.remove(padID, account: account, undoManager: undoManager)
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
                        favorites.toggle(questionID, title: item.title, account: account, undoManager: undoManager)
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
}
