//
//  PadsView+Sidebar.swift
//  coderpad
//

import AppKit
import SwiftUI

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

    var availableStates: [PadState] {
        Array(Set(pads.map(\.status))).sorted { $0.label < $1.label }
    }

    var availableLanguages: [String] {
        Array(Set(pads.compactMap { $0.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }

    var availableOwners: [String] {
        Array(Set(pads.map(\.ownerEmail)).filter { !$0.isEmpty }).sorted()
    }

    var availableTeams: [String] {
        Array(Set(pads.compactMap { $0.team?.name })).sorted()
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
        updatedWindow = PadDateWindow(); createdWindow = PadDateWindow()
    }

    var sidebar: some View {
        FilterableListView(
            isLoading: isLoading,
            isEmpty: pads.isEmpty,
            error: error,
            loadingMessage: "Loading pads…",
            onReload: { await reload() },
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
            // extending it to a multi-row selection.
            .onCopyCommand(perform: copyLinkCommand(
                selectedPadsInOrder.isEmpty ? nil
                    : selectedPadsInOrder.map(\.url).joined(separator: "\n")
            ))
    }

    /// The selected pads in the order they appear in the list (not the selection
    /// set's arbitrary order), so a multi-row Copy or Delete reads top to bottom.
    private var selectedPadsInOrder: [Pad] {
        filtered.filter { selectedIDs.contains($0.id) }
    }

    private var padList: some View {
        // Wrap in a reader so a restored selection can be scrolled into view on
        // launch (see `pendingScrollToID`); the reader sits outside the `.id` below
        // so its proxy survives the filter-driven list rebuilds.
        ScrollViewReader { proxy in
            List(selection: $selectedIDs) {
                ForEach(filtered) { pad in
                    padRow(pad)
                        .tag(pad.id)
                        .installsTableDoubleClick(doubleClickProxy)
                        // Swipe from the leading edge to pin/unpin the pad, mirroring the
                        // questions list's favorite swipe (#348). Full swipe favorites in
                        // one gesture since it's a harmless, reversible toggle.
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            favoriteSwipeButton(pad)
                        }
                        // Full swipe is allowed because it only opens the confirmation
                        // dialog below — it never deletes outright, so an accidental
                        // swipe is recoverable.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                padPendingDelete = pad
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .disabled(isReadOnly)
                        }
                }
            }
            .listStyle(.inset)
            // Re-identify the list whenever the *filter* changes so SwiftUI does a fresh
            // render (the fast path — same as the initial load) instead of an in-place
            // diff of a handful of rows against thousands, which is what made clearing a
            // filter slow on large orgs. Keyed on `filterSignature` only, so background
            // `pads` refreshes still take the cheap incremental diff and keep scroll
            // position. `transaction` then suppresses the cross-fade between identities.
            // The sort joins the key too: changing it reorders every row, so a fresh
            // render beats animating a wholesale reorder (#361).
            .id("\(filterSignature)|\(sort.rawValue)")
            .transaction { $0.animation = nil }
            // Scroll the restored pad into view once, then clear the request so the
            // user's own scrolling afterward is never overridden.
            .onChange(of: pendingScrollToID) { _, id in
                guard let id else { return }

                proxy.scrollTo(id, anchor: .center)
                pendingScrollToID = nil
            }
        }
    }

    private func padRow(_ pad: Pad) -> some View {
        PadRow(
            pad: pad,
            isChanged: PadListLogic.hasNewActivitySinceOpen(
                pad, lastOpened: openedStore.lastOpened(pad.id, account: accounts.currentAccountID)
            ),
            account: accounts.currentAccountID,
            isFavorite: favoritePads.isFavorite(pad.id, account: accounts.currentAccountID),
            onToggleFavorite: {
                guard let account = accounts.currentAccountID else { return }

                favoritePads.toggle(pad.id, account: account)
            }
        )
        .contextMenu { padContextMenu(pad) }
    }

    /// The leading-swipe button that pins or unpins a pad as a favorite (#348),
    /// mirroring the questions list's favorite swipe. Yellow to match the star used
    /// throughout the sidebar's Favorite Pads section.
    @ViewBuilder
    func favoriteSwipeButton(_ pad: Pad) -> some View {
        let isFavorite = favoritePads.isFavorite(pad.id, account: accounts.currentAccountID)
        Button {
            guard let account = accounts.currentAccountID else { return }

            favoritePads.toggle(pad.id, account: account)
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: isFavorite ? "star.slash" : "star")
        }
        .tint(.yellow)
    }

    /// Right-click actions for a pad row. These are the quick, self-contained
    /// operations (open, copy, share, narrow the list); the destructive lifecycle
    /// actions stay behind the detail view's confirmations, reached by selecting
    /// the pad first.
    @ViewBuilder
    func padContextMenu(_ pad: Pad) -> some View {
        // Right-clicking a row that's part of a multi-row selection acts on the whole
        // selection, the way Finder does; otherwise it's the usual single-row menu.
        if selectedIDs.count > 1, selectedIDs.contains(pad.id) {
            bulkContextMenu
        } else {
            singlePadContextMenu(pad)
        }
    }

    /// The right-click menu for a multi-row selection: copy every selected pad's
    /// link, or delete them all behind a confirmation.
    @ViewBuilder
    private var bulkContextMenu: some View {
        let pads = selectedPadsInOrder
        Button {
            Clipboard.copy(pads.map(\.url).joined(separator: "\n"))
        } label: {
            Label("Copy \(pads.count) Pad Links", systemImage: "link")
        }
        Divider()
        Button(role: .destructive) {
            padsPendingBulkDelete = pads
        } label: {
            Label("Delete \(pads.count) Pads…", systemImage: "trash")
        }
        .disabled(isReadOnly)
    }

    /// The usual single-row right-click menu: open, share, copy id/url, narrow the
    /// list to the owner, or delete behind a confirmation.
    @ViewBuilder
    private func singlePadContextMenu(_ pad: Pad) -> some View {
        Button {
            selectedIDs = [pad.id]
            openPad(pad)
        } label: {
            Label("Open Pad", systemImage: "doc.text.image")
        }
        if let url = pad.webURL {
            ShareLink(item: url) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        Divider()
        Button {
            Clipboard.copy(pad.id)
        } label: {
            Label("Copy Pad ID", systemImage: "number")
        }
        Button {
            Clipboard.copy(pad.url)
        } label: {
            Label("Copy Pad URL", systemImage: "link")
        }
        Divider()
        Button {
            ownerFilter = pad.ownerEmail
        } label: {
            Label("Show Pads from \(directory.display(pad.ownerEmail))", systemImage: "person")
        }
        Divider()
        // Opens the same confirmation dialog as the row's swipe action — a
        // right-click route to Delete alongside the swipe.
        Button(role: .destructive) {
            padPendingDelete = pad
        } label: {
            Label("Delete…", systemImage: "trash")
        }
        .disabled(isReadOnly)
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
