//
//  PadsView+Sidebar.swift
//  coderpad
//

// swiftlint:disable file_length

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif
import FastList
import MacPullToRefresh
import SwiftUI
import UniformTypeIdentifiers

extension PadsView {
    @ViewBuilder
    var sidebar: some View {
        #if os(iOS)
            if horizontalSizeClass == .compact {
                decoratedSidebar(compactSidebar)
            } else {
                decoratedSidebar(standardSidebar)
            }
        #else
            decoratedSidebar(standardSidebar)
        #endif
    }

    private var standardSidebar: some View {
        FilterableListView(
            isLoading: isLoading && !pads.isEmpty,
            isEmpty: pads.isEmpty && !isLoading,
            error: error,
            loadingMessage: "Refreshing pads…",
            onReload: { await reload() },
            errorView: { error, retry in APIErrorView(error: error, onRetry: retry, accountID: owningAccountID) },
            savedSearches: { EmptyView() },
            filters: { filterBar },
            list: { padCollection }
        )
    }

    #if os(iOS)
        private var compactSidebar: some View {
            List(selection: $selectedIDs) {
                compactFilterSection
                compactStateSection
                ForEach(filtered) { pad in
                    compactPadRow(pad)
                }
            }
            .listStyle(.plain)
            .refreshable { await reload(force: true) }
            .onKeyPress(.return) {
                guard let selection else { return .ignored }

                openPad(selection)
                return .handled
            }
            .focusedSceneValue(\.focusedPad, selection)
            .focusedSceneValue(\.focusedPadAccountID, owningAccountID)
        }

        @ViewBuilder
        private var compactFilterSection: some View {
            if !pads.isEmpty || hasActiveFilters || !search.isEmpty {
                filterBar
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
            }
        }

        @ViewBuilder
        private var compactStateSection: some View {
            if pads.isEmpty, isLoading {
                ProgressView("Refreshing pads…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
            } else if let error, pads.isEmpty {
                APIErrorView(error: error, onRetry: { Task { await reload() } }, accountID: owningAccountID)
                    .listRowSeparator(.hidden)
            } else if pads.isEmpty {
                ContentUnavailableView("No Pads", systemImage: "doc.text")
                    .listRowSeparator(.hidden)
            } else if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Pads", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Clear Filters") {
                        search = ""
                        clearAllFilters()
                    }
                }
                .listRowSeparator(.hidden)
            }
        }

        private func compactPadRow(_ pad: Pad) -> some View {
            PadRowHostableContent(
                pad: pad,
                ownerDisplay: directory.display(pad.ownerEmail),
                isFavorite: favoritePads.isFavorite(pad.id, account: accounts.currentAccountID),
                onToggleFavorite: {
                    guard let account = accounts.currentAccountID else { return }

                    favoritePads.toggle(pad.id, title: pad.title, account: account, undoManager: undoManager)
                }
            )
            .accessibilityIdentifier("pad-row-\(pad.id)")
            .tag(pad.id)
            .contentShape(Rectangle())
            .onTapGesture { selectedIDs = [pad.id] }
            .swipeActions(edge: .leading) {
                Button {
                    guard let account = accounts.currentAccountID else { return }

                    favoritePads.toggle(pad.id, title: pad.title, account: account, undoManager: undoManager)
                } label: {
                    let isFavorite = favoritePads.isFavorite(pad.id, account: accounts.currentAccountID)
                    Label(isFavorite ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                          systemImage: isFavorite ? "star.slash" : "star.fill")
                }
                .tint(.yellow)
            }
            .swipeActions(edge: .trailing) {
                if !isReadOnly {
                    Button(role: .destructive) {
                        padPendingDelete = pad
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .contextMenu {
                Button("Open in Browser") { openPad(pad) }
                Button("Open Pad Window") { openPadDetailWindow(pad) }
                Button("Copy Pad ID") { Clipboard.copy(pad.id) }
                Button("Copy Pad URL") { Clipboard.copy(pad.url) }
                Button("Show Pads from \(directory.display(pad.ownerEmail))") {
                    ownerFilter = pad.ownerEmail
                }
                if !isReadOnly {
                    Divider()
                    Button("Delete…", role: .destructive) { padPendingDelete = pad }
                }
            }
        }
    #endif

    // swiftlint:disable:next function_body_length
    private func decoratedSidebar(_ content: some View) -> some View {
        content
            // Bubble the count up to the window toolbar (shown beneath the "Pads" title)
            // rather than as an inline bar above the list.
            .reportsSectionCount(countSubtitle)
            // The search field itself lives on the `NavigationSplitView` in `MainSplit`
            // (trailing window toolbar, Finder-style); this column only owns the section
            // actions below.
            .toolbar(id: "pads") {
                #if os(iOS)
                    ToolbarItem(id: "pads-actions", placement: .topBarTrailing) {
                        HStack(spacing: 8) {
                            Button { showCreate = true } label: {
                                Label("New Pad", systemImage: "plus")
                            }
                            .help("Create a new pad (⌘N)")
                            .disabled(client.apiKey.isEmpty || isReadOnly)

                            Menu {
                                Button {
                                    search = ""
                                    clearAllFilters()
                                } label: {
                                    Label("All Pads", systemImage: hasActiveFilters ? "tray" : "checkmark")
                                }

                                ForEach(DefaultSearch.padDefaults(me: accounts.currentAccount?.userEmail)) { item in
                                    Button {
                                        apply(item.search)
                                    } label: {
                                        Label(item.search.name,
                                              systemImage: isActiveSearch(item.search) ? "checkmark" : item.icon)
                                    }
                                }
                            } label: {
                                Label("Suggestions", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            .help("Apply a suggested pad filter")
                            .accessibilityLabel("Suggested pad filters")

                            Menu {
                                PadSortMenuContent(sort: $sort)
                            } label: {
                                Label("Sort", systemImage: "arrow.up.arrow.down")
                            }
                            .help("Sort pads")
                            .accessibilityLabel("Sort pads")
                        }
                    }
                #else
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
                #endif
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
                    } actions: {
                        Button("Clear Filters") {
                            search = ""
                            clearAllFilters()
                        }
                    }
                }
            }
            // ↑/↓ move the selection natively; Return opens the selected pad in the
            // user's browser.
            .onKeyPress(.return) {
                guard let selection else { return .ignored }

                openPad(selection)
                return .handled
            }
            .macPullToRefresh { await reload(force: true) }
            // Scene-scoped, not view-scoped: the Pad menu commands (Copy Pad ID/URL,
            // Open in Browser) should stay enabled whenever this window is frontmost and
            // a pad is selected — not only while the list itself holds keyboard focus.
            .focusedSceneValue(\.focusedPad, selection)
            .focusedSceneValue(\.focusedPadAccountID, owningAccountID)
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
                ownerDisplay: directory.display(pad.ownerEmail),
                isFavorite: favoritePads.isFavorite(pad.id, account: accounts.currentAccountID),
                onToggleFavorite: {
                    guard let account = accounts.currentAccountID else { return }

                    favoritePads.toggle(pad.id, title: pad.title, account: account, undoManager: undoManager)
                }
            )
            .accessibilityIdentifier("pad-row-\(pad.id)")
            .fastListRowManualSelection(id: pad.id, selection: $selectedIDs)
            // iPad: drag onto the sidebar Favorites to pin, or out to Safari/Notes/Split View.
            .favoriteDraggable(padFavoritePayload(pad), title: pad.title.isEmpty ? pad.id : pad.title)
            // iPad: the row's context menu with a compact preview (macOS uses the FastList
            // `NSMenu` path below instead).
            .favoriteRowContextMenu(padTableMenuItems(pad), title: pad.title.isEmpty ? pad.id : pad.title)
        }
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

                favoritePads.toggle(pad.id, title: pad.title, account: account, undoManager: undoManager)
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
            .onDragSession(began: FavoriteDragLifecycle.onBegan(in: windowScope),
                           ended: FavoriteDragLifecycle.onEnded(in: windowScope))
        #endif
        #if DEBUG
            // Still prints the per-selection stall; row evals should now be ~0 since
            // NSTableView doesn't re-host rows on a selection change (#439).
            .onChange(of: selectedIDs) { SelectionProfiler.selectionChanged() }
        #endif
    }

    /// Reloads the rows when the current account's favourites change. The store's
    /// revision stands in for the joined favourite ids this used to rebuild on every
    /// body pass, selection-only re-renders included (#2101).
    private var padListReloadID: FavoritesReloadID {
        FavoritesReloadID(account: accounts.currentAccountID, revision: favoritePads.revision)
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

    // The drag payload for a pad row in the `NSTableView`-backed list: the pad's web
    // URL (so external apps receive a link) plus the internal `FavoriteDrop` JSON (so
    // it can be dropped on the sidebar Favorites to pin it, #297). Built at the AppKit
    // layer because the hosted SwiftUI content is hit-transparent — a SwiftUI
    // `.draggable` there would never grab.
    #if os(macOS)
        private func padPasteboardItem(_ pad: Pad) -> NSPasteboardItem? {
            if selectedIDs.count > 1, selectedIDs.contains(pad.id) {
                return multiLinkPasteboardItem(selectedPadsInOrder.map(\.url))
            }

            guard let url = pad.webURL else { return nil }

            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .URL)
            item.setString(url.absoluteString, forType: .string)
            if let account = accounts.currentAccountID,
               // The shared coder: this builds a pasteboard item per drag, so a
               // dragged row was paying for a fresh encoder each time (#2104).
               let data = try? SharedCoders.encoder.encode(
                   FavoriteDrop.pad(account: account, id: pad.id, title: pad.title.isEmpty ? pad.id : pad.title)
               ) {
                item.setData(data, forType: NSPasteboard.PasteboardType(UTType.coderpadFavorite.identifier))
            }
            return item
        }
    #endif

    /// The right-click menu for a pad row in the `NSTableView`-backed list, built as
    /// AppKit `MenuItem`s (the hosted SwiftUI content is hit-transparent, so a
    /// selection, the way Finder does; otherwise it's the single-row menu. (Share is
    /// selection, the way Finder does; otherwise it is the single-row menu. (Share is
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

                    favoritePads.toggle(pad.id, title: pad.title, account: account, undoManager: undoManager)
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

    /// Open a pad in the user's configured browser. Resolved via the account's
    /// base URL when the pad's own `url` field is absent or malformed, so pads
    /// from self-hosted/regional servers still open (#1010), matching the
    /// ID-routed (#731) and create-and-open (#781) paths.
    func openPad(_ pad: Pad) {
        let base = accounts.currentAccount?.resolvedBaseURL ?? CoderPadClient.defaultBaseURL
        guard let url = pad.webURL(fallbackBase: base) else { return }

        BrowserSettings.openExternally(url)
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
