//
//  PadsView+Sidebar.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import MacPullToRefresh
import SwiftUI
import UniformTypeIdentifiers

extension PadsView {
    static let dateRangeOptions = PadDateRange.options

    /// The filtered list, memoized for the duration of one render. `filtered` is
    /// read several times per `body` evaluation (the list, the result count, the
    /// empty state, and the bulk-action menu), and re-running the full O(n) filter
    /// on each read beach-balled large pad lists the moment a filter changed.
    /// `refreshFiltered()` recomputes it once at the top of `body`, so every read in
    /// that pass is O(1) and always current.
    var filtered: [Pad] {
        filteredCache.pads
    }

    func refreshFiltered() {
        // Skip the filter+sort when nothing that affects the result changed. `body`
        // re-runs several times per click as the selection settles, and only the
        // selection differs across those passes — re-filtering and re-sorting the
        // whole org each time is what made clicking a row slow on large lists (#395).
        let key = FilteredPadsCache.Key(
            padsRevision: padsRevision,
            filterSignature: filterSignature,
            sortRawValue: sort.rawValue,
            directoryCount: directory.nameByEmail.count
        )
        guard filteredCache.key != key else { return }

        let matched = PadListLogic.filter(
            pads,
            using: PadFilterCriteria(
                search: search,
                state: stateFilter,
                language: languageFilter,
                owner: ownerFilter,
                team: teamFilter,
                type: typeFilter,
                updated: updatedWindow,
                created: createdWindow
            ),
            display: directory.display
        )
        filteredCache.pads = sort.sorted(matched)
        filteredCache.key = key
    }

    /// The pad to select after the pad with `id` is deleted. Picks the row that
    /// takes the deleted row's position (the next one down), falling back to the
    /// previous pad when the deleted pad was last, and to `nil` when it was the
    /// only visible pad. Resolved against `filtered` — the list the user actually
    /// sees — so a hidden pad never becomes the new selection.
    func neighborSelection(forDeleted id: String) -> Pad? {
        let visible = filtered
        // If the deleted pad isn't in the visible list (e.g. filters changed after it
        // was selected), fall back to the first visible pad rather than blanking the
        // detail pane when there are still pads to show.
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.first }

        if visible.indices.contains(index + 1) { return visible[index + 1] }
        if visible.indices.contains(index - 1) { return visible[index - 1] }
        return nil
    }

    /// The Updated and Created date filters are independent, so each active one
    /// counts on its own.
    var activeFilterCount: Int {
        (stateFilter != nil ? 1 : 0)
            + [languageFilter, ownerFilter, teamFilter, typeFilter].compactMap(\.self).count
            + (updatedWindow.isActive ? 1 : 0)
            + (createdWindow.isActive ? 1 : 0)
    }

    /// Resets every live filter. Shared by the toolbar Clear button and the
    /// filtered empty state so the two never drift.
    func clearAllFilters() {
        stateFilter = nil; languageFilter = nil
        ownerFilter = nil; teamFilter = nil; typeFilter = nil
        updatedWindow = DateWindow(); createdWindow = DateWindow()
    }

    var sidebar: some View {
        FilterableListView(
            isLoading: isLoading,
            isEmpty: pads.isEmpty,
            error: error,
            loadingMessage: "Loading pads…",
            onReload: { await reload() },
            errorView: { error, retry in APIErrorView(error: error, onRetry: retry) },
            savedSearches: { savedSearchesBar },
            filters: { filterBar },
            list: { padCollection }
        )
        // Bubble the count up to the window toolbar (shown beneath the "Pads" title)
        // rather than as an inline bar above the list.
        .reportsSectionCount(countSubtitle)
        // The search field itself lives on the `NavigationSplitView` in `MainSplit`
        // (trailing window toolbar, Finder-style); this column only owns the section
        // actions below.
        .toolbar(id: "pads") {
            // Hidden by default — reachable via View ▸ Customize Toolbar…, the
            // File ▸ Reload command (⌘R), or pull-to-refresh (#413).
            ToolbarItem(id: "reload", placement: .automatic) {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            .defaultCustomization(.hidden)
            // Grouped beside Reload at the list column's leading edge rather than
            // floating at the trailing edge: a `.primaryAction` here shares the
            // window's trailing region with the detail pane's actions, so selecting
            // a pad would shove this button leftward. Anchoring it left keeps it put.
            // (#337 tried `.navigation` to reclaim the collapsed-sidebar inset, but
            // that anchors the cluster left of the title — reverted.)
            ToolbarItem(id: "new-pad", placement: .automatic) {
                Button { showCreate = true } label: {
                    Label("New Pad", systemImage: "plus")
                }
                .help("Create a new pad (⌘N)")
                .accessibilityLabel("New Pad")
                .disabled(client.apiKey.isEmpty || isReadOnly)
            }
            ToolbarItem(id: "sort", placement: .automatic) {
                Menu {
                    PadSortMenuContent(sort: $sort)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort pads")
                .accessibilityLabel("Sort pads")
            }
            // Opt-in detail-pane toggle, hidden by default (#404).
            DetailPaneToggleToolbarContent()
        }
    }

    /// The pad list plus the modifiers around it (empty state, Return-to-open,
    /// pull-to-refresh, focused-pad command target).
    private var padCollection: some View {
        padList
            // When filters exclude everything, explain why rather than leaving a blank
            // list that reads like a load failure.
            .overlay {
                if filtered.isEmpty, !pads.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Pads", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No pads match the current filters.")
                    } actions: {
                        Button("Clear Filters") { clearAllFilters() }
                    }
                }
            }
            // ↑/↓ move the selection natively; Return opens the selected pad in the
            // in-app browser (honoring the user's browser preference).
            .onKeyPress(.return) {
                guard let selection else { return .ignored }

                openPad(selection)
                return .handled
            }
            .macPullToRefresh { await reload() }
            // Scene-scoped, not view-scoped: the Pad menu commands (Copy Pad ID/URL,
            // Open in Browser) should stay enabled whenever this window is frontmost and
            // a pad is selected — not only while the list itself holds keyboard focus.
            .focusedSceneValue(\.focusedPad, selection)
            // Edit ▸ Copy / ⌘C copies the selected pads' web URLs (one per line) while
            // the list holds focus, matching the row's "Copy Pad URL" action and
            // extending it to a multi-row selection. The O(N) `selectedPadsInOrder` scan
            // is built lazily (only on an actual copy); the per-render gate is the O(1)
            // empty-selection check, so it stays off the click path.
            #if os(macOS)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedIDs.isEmpty) {
                selectedPadsInOrder.map(\.url).joined(separator: "\n")
            })
            #endif
    }

    /// The selected pads in the order they appear in the list (not the selection
    /// set's arbitrary order), so a multi-row Copy or Delete reads top to bottom.
    private var selectedPadsInOrder: [Pad] {
        filtered.filter { selectedIDs.contains($0.id) }
    }

    private var padList: some View {
        // NSTableView-backed (#439): a SwiftUI `List` rebuilds every row on each
        // selection and stalled large lists, and `.equatable()` rows can't be made
        // both lazy and click-safe. An `NSTableView` recycles only visible rows — like
        // Mail — so the list does ~0 work on selection regardless of length, while each
        // row still hosts the SwiftUI content (favorite star, drag, context menu).
        FastList(filtered, selection: $selectedIDs) { pad in
            PadRowHostableContent(
                pad: pad,
                isChanged: PadListLogic.hasNewActivitySinceOpen(
                    pad, lastOpened: openedStore.lastOpened(pad.id, account: accounts.currentAccountID)
                ),
                ownerDisplay: directory.display(pad.ownerEmail),
                isFavorite: favoritePads.isFavorite(pad.id, account: accounts.currentAccountID),
                onToggleFavorite: {
                    guard let account = accounts.currentAccountID else { return }

                    favoritePads.toggle(pad.id, title: pad.title, account: account)
                }
            )
            .fastListRowManualSelection(id: pad.id, selection: $selectedIDs)
            // iPad: drag onto the sidebar Favorites to pin, or out to Safari/Notes/Split View.
            .favoriteDraggable(padFavoritePayload(pad), title: pad.title.isEmpty ? pad.id : pad.title)
            // iPad: the row's context menu with a compact preview (macOS uses the FastList
            // `NSMenu` path below instead).
            .favoriteRowContextMenu(padTableMenuItems(pad), title: pad.title.isEmpty ? pad.id : pad.title)
        }
        .rowHeight(FastListRowMetrics.macHeight)
        .reloadID(padListReloadID)
        .onDoubleClick { openPadDetailWindow($0) }
        .onReturnKey { openPad($0) }
        .swipeActions(edge: .leading) { pad in
            let starred = favoritePads.isFavorite(pad.id, account: accounts.currentAccountID)
            return [SwipeAction(
                title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                tint: Color(platformColor: .systemYellow),
                systemImage: starred ? "star.slash" : "star.fill"
            ) {
                guard let account = accounts.currentAccountID else { return }

                favoritePads.toggle(pad.id, title: pad.title, account: account)
            }]
        }
        .swipeActions(edge: .trailing) { pad in
            isReadOnly ? [] : [SwipeAction(title: String(localized: "Delete"), role: .destructive,
                                           systemImage: "trash") {
                    padPendingDelete = pad
                }]
        }
        #if os(macOS)
        .onRowDrag { padPasteboardItem($0) }
        #endif
        // iPad drag is attached to the row content above via `.favoriteDraggable` so it can
        // carry the favorite payload alongside the URL; `FastList.onRowDragURL` (URL only)
        // would add a second, conflicting `.draggable`. The iPad context menu is likewise
        // attached to the row content (`.favoriteRowContextMenu`) so its long-press preview
        // stays compact; `FastList`'s `NSMenu` path here is macOS-only.
        #if os(macOS)
        .rowContextMenu { padTableMenuItems($0) }
        #endif
        .onTopRowChange { scheduleTopRowPersistence($0) }
        .scrollToRow(id: pendingScrollToID) { pendingScrollToID = nil }
        #if os(macOS)
        .onDragSession(began: FavoriteDragLifecycle.onBegan, ended: FavoriteDragLifecycle.onEnded)
        #endif
        #if DEBUG
            // Still prints the per-selection stall; row evals should now be ~0 since
            // NSTableView doesn't re-host rows on a selection change (#439).
        .onChange(of: selectedIDs) { SelectionProfiler.selectionChanged() }
        #endif
    }

    private var padListReloadID: String {
        let account = accounts.currentAccountID
        return favoritePads.favorites(account: account).joined(separator: "\u{1F}")
    }

    /// The iPad drag payload for a pad row: the internal `FavoriteDrop` (so it can be
    /// dropped on the sidebar Favorites to pin it, #297) plus the web URL (so external
    /// drops still receive a link). `nil` — non-draggable — when there's no current
    /// account or the pad has no URL, mirroring `padPasteboardItem` on macOS.
    func padFavoritePayload(_ pad: Pad) -> FavoriteDragPayload? {
        guard let account = accounts.currentAccountID, let url = pad.webURL else { return nil }

        return FavoriteDragPayload(
            drop: .pad(account: account, id: pad.id, title: pad.title.isEmpty ? pad.id : pad.title),
            url: url
        )
    }

    /// The drag payload for a pad row in the `NSTableView`-backed list: the pad's web
    /// URL (so external apps receive a link) plus the internal `FavoriteDrop` JSON (so
    /// it can be dropped on the sidebar Favorites to pin it, #297). Built at the AppKit
    /// layer because the hosted SwiftUI content is hit-transparent — a SwiftUI
    /// `.draggable` there would never grab.
    #if os(macOS)
    private func padPasteboardItem(_ pad: Pad) -> NSPasteboardItem? {
        guard let url = pad.webURL else { return nil }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.absoluteString, forType: .string)
        if let account = accounts.currentAccountID,
           let data = try? JSONEncoder().encode(
               FavoriteDrop.pad(account: account, id: pad.id, title: pad.title.isEmpty ? pad.id : pad.title)
           ) {
            item.setData(data, forType: NSPasteboard.PasteboardType(UTType.coderpadFavorite.identifier))
        }
        return item
    }
    #endif

    /// The right-click menu for a pad row in the `NSTableView`-backed list, built as
    /// AppKit `MenuItem`s (the hosted SwiftUI content is hit-transparent, so a
    /// SwiftUI `.contextMenu` can't be used). A multi-row selection acts on the whole
    /// selection, the way Finder does; otherwise it's the single-row menu. (Share is
    /// reachable from the detail pane.)
    func padTableMenuItems(_ pad: Pad) -> [MenuItem] {
        if selectedIDs.count > 1, selectedIDs.contains(pad.id) {
            let pads = selectedPadsInOrder
            return [
                .button(title: String(localized: "Copy \(pads.count) Pad Links")) {
                    Clipboard.copy(pads.map(\.url).joined(separator: "\n"))
                },
                .separator,
                .button(title: String(localized: "Delete \(pads.count) Pads…"),
                        isEnabled: !isReadOnly,
                        role: .destructive) {
                    padsPendingBulkDelete = pads
                }
            ]
        }
        let starred = favoritePads.isFavorite(pad.id, account: accounts.currentAccountID)
        return [
            .button(title: String(localized: "Open Pad")) {
                selectedIDs = [pad.id]
                openPad(pad)
            },
            .button(title: starred ? String(localized: "Remove from Favorites")
                : String(localized: "Add to Favorites")) {
                    guard let account = accounts.currentAccountID else { return }

                    favoritePads.toggle(pad.id, title: pad.title, account: account)
                },
            .separator,
            .button(title: String(localized: "Copy Pad ID")) { Clipboard.copy(pad.id) },
            .button(title: String(localized: "Copy Pad URL")) { Clipboard.copy(pad.url) },
            .separator,
            .button(title: String(localized: "Show Pads from \(directory.display(pad.ownerEmail))")) {
                ownerFilter = pad.ownerEmail
            },
            .separator,
            .button(title: String(localized: "Delete…"), isEnabled: !isReadOnly, role: .destructive) {
                padPendingDelete = pad
            }
        ]
    }

    /// Open a pad honoring the user's browser preference: externally when chosen,
    /// otherwise in a dedicated in-app browser window. The list has no inline
    /// browser pane of its own, so the in-app case opens a separate window —
    /// matching the "Open Pad in Browser" menu command.
    func openPad(_ pad: Pad) {
        guard let url = pad.webURL else { return }

        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            openWindow(id: "pad-browser", value: url)
        }
    }

    /// Opens a pad's native detail in its own window (#354), the pad counterpart to
    /// double-clicking a question row. Distinct from ``openPad(_:)``, which opens
    /// the pad's live URL in the browser.
    func openPadDetailWindow(_ pad: Pad) {
        openWindow(id: "pad", value: PadWindowID(account: accounts.currentAccountID, id: pad.id))
    }

    /// How many pads the current filters resolve to, shown as the window's toolbar
    /// subtitle beneath the "Pads" title so the list length is legible at a glance
    /// and a short list reads as "filtered to a few" rather than "failed to load".
    /// Empty when the org has no pads at all, where a "0 pads" line would just
    /// restate the empty list.
    var countSubtitle: String {
        guard !pads.isEmpty else { return "" }

        let count = filtered.count
        return count == 1 ? String(localized: "\(count) pad") : String(localized: "\(count) pads")
    }
}
