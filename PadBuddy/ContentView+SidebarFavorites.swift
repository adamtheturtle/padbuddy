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
    ///
    /// Derived through the memo in `refreshedFavoriteEntries()` rather than read
    /// directly, so an unrelated re-render doesn't rebuild it (#2107).
    func computeFavoriteEntries() -> [FavoriteEntry] {
        if isMergedView {
            // One index per account, built once — the merged list interleaves accounts,
            // so resolving each row on its own would rebuild these lookups for every
            // row in every account (#2529).
            let indexes = Dictionary(
                accounts.mergeableAccounts.map { ($0.id, makeTitleIndex(forAccount: $0.id)) },
                uniquingKeysWith: { first, _ in first }
            )
            return favoritesOrder.merged(present: presentMergedRefs()).compactMap { item in
                guard let index = indexes[item.account] else { return nil }

                return favoriteEntry(forAccount: item.account, ref: item.ref,
                                     namespaced: true, index: index)
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

        let index = makeTitleIndex(forAccount: account)
        let ordered = favoritesOrder.order(present: presentRefs(account: account), account: account)
        return ordered.compactMap {
            favoriteEntry(forAccount: account, ref: $0, namespaced: namespaced, index: index)
        }
    }

    /// One account's title lookups and membership sets.
    ///
    /// These used to be rebuilt inside the per-row call — four dictionaries over the
    /// entire pads and questions caches, plus two linear membership scans, for every
    /// favourite — which made a sidebar render quadratic in the number of favourites
    /// and stalled the UI on accounts with many of them (#2529).
    private func makeTitleIndex(forAccount account: UUID) -> FavoriteTitleIndex {
        FavoriteTitleIndex(
            padTitles: Dictionary(
                padsCache.cached(account).compactMap { pad in pad.title.isEmpty ? nil : (pad.id, pad.title) },
                uniquingKeysWith: { first, _ in first }
            ),
            storedPadTitles: Dictionary(
                favoritePads.titledFavorites(account: account).map { ($0.id, $0.title) },
                uniquingKeysWith: { first, _ in first }
            ),
            cacheTitles: Dictionary(
                questionsCache.cached(account).map { ($0.id, $0.displayTitle) },
                uniquingKeysWith: { first, _ in first }
            ),
            storedTitles: Dictionary(
                favorites.titledFavorites(account: account).map { ($0.id, $0.title) },
                uniquingKeysWith: { first, _ in first }
            ),
            padMembers: Set(favoritePads.favorites(account: account)),
            questionMembers: Set(favorites.favorites(account: account))
        )
    }

    /// The per-section title lookups and membership sets a favourite row resolves
    /// against, built once per render rather than once per row.
    private struct FavoriteTitleIndex {
        let padTitles: [String: String]
        let storedPadTitles: [String: String]
        let cacheTitles: [Int: String]
        let storedTitles: [Int: String]
        let padMembers: Set<String>
        let questionMembers: Set<Int>
    }

    private func favoriteEntry(forAccount account: UUID, ref: FavoriteRef, namespaced: Bool,
                               index: FavoriteTitleIndex) -> FavoriteEntry? {
        /// Whitespace-only titles count as absent, or they'd beat the slug /
        /// "Question #id" fallbacks and render blank rows (#1680, #1681).
        func presentable(_ title: String?) -> String? {
            guard let title else { return nil }

            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        switch ref {
        case let .pad(padID):
            guard index.padMembers.contains(padID) else { return nil }

            // Prefer the live cache title (so renames show through), then the title
            // captured when the pad was pinned (#654), and only fall back to the bare
            // slug for a legacy favourite whose pad hasn't loaded yet.
            return FavoriteEntry(
                id: namespaced ? "\(account.uuidString)-pad-\(padID)" : "pad-\(padID)",
                ref: ref,
                account: namespaced ? account : nil,
                title: presentable(index.padTitles[padID])
                    ?? presentable(index.storedPadTitles[padID])
                    ?? padID
            )

        case let .question(questionID):
            guard index.questionMembers.contains(questionID) else { return nil }

            let resolved = presentable(index.cacheTitles[questionID])
                ?? presentable(index.storedTitles[questionID])
                ?? "Question #\(questionID)"
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
    ///
    /// The drag-in-flight signal comes from AppKit's `NSDraggingSession` callbacks,
    /// which have no iOS counterpart — so on iPad the monitor never turned true, the
    /// section stayed hidden with nothing favourited, and there was no target for the
    /// documented `.draggable` favourite drop to land on (#2513). There, an empty
    /// section is shown instead: a permanent header is a far better trade than a
    /// feature that cannot be started.
    @ViewBuilder
    var favoritesSection: some View {
        let entries = refreshedFavoriteEntries()
        if !entries.isEmpty || showsEmptyFavoritesSection {
            Section("Favorites", isExpanded: $favoritesSectionExpanded) {
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
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
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
                            sectionBinding: sectionBinding,
                            canMoveUp: index > entries.startIndex,
                            canMoveDown: index < entries.index(before: entries.endIndex),
                            moveUp: { moveFavorite(item, by: -1, in: entries) },
                            moveDown: { moveFavorite(item, by: 1, in: entries) },
                            restoreDefaultOrder: restoreDefaultFavoriteOrder
                        ))
                    }
                )
            }
            if entries.isEmpty {
                favoriteDropSpacer
            }
        }
        .modifier(FavoriteDropChrome(isHighlighted: droppingFavorites))
        .onDrop(of: [.coderpadFavoriteReorder, .coderpadFavorite], isTargeted: $droppingFavorites) { providers in
            let reorders = providers.filter {
                $0.hasItemConformingToTypeIdentifier(UTType.coderpadFavoriteReorder.identifier)
            }
            let adds = providers.filter {
                !$0.hasItemConformingToTypeIdentifier(UTType.coderpadFavoriteReorder.identifier)
                    && $0.hasItemConformingToTypeIdentifier(UTType.coderpadFavorite.identifier)
            }
            if let reorder = reorders.first {
                loadFavoriteReorder(from: reorder) { reorder in
                    reorderTargetID = nil
                    moveFavoriteToEnd(reorder)
                }
            }
            // Batch-decoded so a multi-item drag pins in its original drag order (#1678).
            loadFavoriteDrops(from: adds) { _ = handleFavoriteDrop($0) }
            // Accept only when something usable was actually offered, so the drop
            // animation doesn't report success for foreign payloads (#1677).
            return !reorders.isEmpty || !adds.isEmpty
        }
    }

    /// One favourite row: a pad opens its pad, a question opens its question, each with the
    /// same glyph its own section uses (a document vs a question bubble) so the kind reads
    /// at a glance without a tinted star (#571). In the merged view the tap queues a pending
    /// merged favourite so the right account's row is selected (per-org ids collide, so the
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
        let canMoveUp: Bool
        let canMoveDown: Bool
        let moveUp: () -> Void
        let moveDown: () -> Void
        let restoreDefaultOrder: () -> Void
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
                if let account = item.account {
                    sectionBinding.wrappedValue = .pads
                    nav.selectMergedFavoritePad(account: account, id: padID)
                } else {
                    nav.showFavoritePad(id: padID)
                }
            }
            .contextMenu {
                favoriteMoveButtons(deps)
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
                    nav.selectMergedFavoriteQuestion(account: account, id: questionID)
                } else {
                    nav.showFavoriteQuestion(id: questionID)
                }
            }
            .contextMenu {
                favoriteMoveButtons(deps)
                removeFavoriteButton {
                    if let account = item.account ?? accountID {
                        favorites.toggle(questionID, title: item.title, account: account, undoManager: undoManager)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func favoriteMoveButtons(_ deps: FavoriteRowDeps) -> some View {
        Button("Move Up", systemImage: "arrow.up", action: deps.moveUp)
            .disabled(!deps.canMoveUp)
        Button("Move Down", systemImage: "arrow.down", action: deps.moveDown)
            .disabled(!deps.canMoveDown)
        Button("Restore Default Order", systemImage: "arrow.counterclockwise",
               action: deps.restoreDefaultOrder)
        Divider()
    }

    private func moveFavorite(_ item: FavoriteEntry, by offset: Int, in entries: [FavoriteEntry]) {
        guard let index = entries.firstIndex(where: { $0.id == item.id }),
              let payload = reorderPayload(item)
        else { return }

        let destination = index + offset
        guard entries.indices.contains(destination) else { return }

        if offset < 0 {
            reorder(payload, before: entries[destination])
        } else if entries.indices.contains(destination + 1) {
            reorder(payload, before: entries[destination + 1])
        } else {
            moveFavoriteToEnd(payload)
        }
        AccessibilityNotification.Announcement(
            offset < 0 ? String(localized: "Moved \(item.title) up", table: "FavoriteReordering")
                : String(localized: "Moved \(item.title) down", table: "FavoriteReordering")
        ).post()
    }

    private func restoreDefaultFavoriteOrder() {
        if isMergedView {
            favoritesOrder.resetMerged(present: presentMergedRefs(), undoManager: undoManager)
        } else if let accountID {
            favoritesOrder.reset(
                present: presentRefs(account: accountID), account: accountID, undoManager: undoManager
            )
        }
        AccessibilityNotification.Announcement(String(localized: "Restored default favorite order")).post()
    }

    /// An empty favourites section's drop zone, revealed *only* while a favorite drag is
    /// in flight (#444) so the section keeps no resting gap (the earlier always-present
    /// 28pt spacer from #440 read as unfinished). When a drag begins, it expands to give
    /// the section's `.onDrop` a non-zero target; on drop/cancel it collapses again. The
    /// `FavoriteDropChrome` highlight still signals droppability while a drag hovers.
    private var favoriteDropSpacer: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: showsEmptyFavoritesSection ? 28 : 0)
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .smooth, value: showsEmptyFavoritesSection)
    }

    /// Whether an empty Favorites section should be present to receive a drop.
    ///
    /// macOS reveals it only while a favourite drag is in flight, so the section keeps
    /// no resting gap (#440/#444). iOS has no drag-session callback to key that off,
    /// so it stays available — see `favoritesSection` (#2513).
    private var showsEmptyFavoritesSection: Bool {
        #if os(macOS)
            favoriteDragMonitor.isDragging(in: windowScope)
        #else
            true
        #endif
    }
}
