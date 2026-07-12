//
//  MergedPadsView+List.swift
//  coderpad
//
//  The view body, list, rows, and lifecycle/dialog modifiers for the combined
//  pads list. Kept out of the primary struct so its body-length stays small.
//

#if os(macOS)
    import AppKit
#endif
import AsyncAlgorithms
import MacPullToRefresh
import SwiftUI

extension MergedPadsView {
    /// The full content with every lifecycle task, selection bridge, sheet, and
    /// confirmation dialog attached. `body` only memoizes the filtered list and
    /// returns this.
    ///
    /// Split across several intermediate `some View` properties rather than one long
    /// modifier chain: a single ~20-modifier chain makes the Swift type-checker infer
    /// one deeply-nested generic type and blows the Release build's 250ms
    /// type-check-timing budget (warnings-as-errors). Each sub-chain type-checks
    /// independently here, so none exceeds the budget. Order is preserved. (#427)
    var decorated: some View {
        decoratedDialogs
    }

    /// `content` plus the per-session lifecycle and the core selection bridge.
    private var decoratedLifecycle: some View {
        content
            .task(id: MergedPadsTaskKey(accountKey: accountKey, phase: scenePhase)) {
                guard scenePhase == .active else { return }

                seedFromCache()
                // Reopen the pad selected last session, once the seeded cache (or the
                // reload below) provides a list to resolve it against.
                restoreSelectedPadIfNeeded()
                // Initial load, then refresh on a timer rebuilt each cycle so an interval
                // change in Settings takes effect on the next tick without restarting the task.
                await reload()
                while !Task.isCancelled {
                    let interval = max(GeneralSettings.refreshInterval, .milliseconds(1))
                    for await _ in AsyncTimerSequence.repeating(every: interval) {
                        await reload()
                        break
                    }
                }
            }
            .onAppear {
                // Restore the filters the list was left with last session before
                // applying any queued navigation request, so person links can override
                // the restored owner/search fields while preserving the rest.
                restoreFilters()
                applyPendingRequest()
                selectedIDs = selection.map { [$0.id] } ?? []
            }
            // Re-persist whenever any filter changes; `filterSignature` shifts for
            // every filter control, so one observer covers them all.
            .onChange(of: filterSignature) { _, _ in persistFilters() }
            // The List edits `selectedIDs`; derive the primary row from it so the
            // detail pane, command target, and per-row bridging keep working off the
            // single `selectedID`. One-way (set → primary), so there's no two-way loop.
            .onChange(of: selectedIDs) { previous, current in
                let primary = MultiSelectLogic.primaryID(previous: previous, current: current)
                if selectedID != primary { selectedID = primary }
                // Resolve the detail-pane `Pad` and persist in the same pass rather than via
                // a separate `onChange(selectedID)`: each extra state write re-runs `body`
                // and rebuilds the list's prepared rows, so collapsing the cascade removes a
                // full rebuild per click on a large merged list (mirrors the PadsView fix).
                if selection?.id != primary {
                    selection = primary.flatMap { id in pad(forID: id) }
                }
                Task { @MainActor in persistSelectedPad() }
            }
    }

    /// The "Mine" preset / favourite / settle-on-selection observers.
    private var decoratedSync: some View {
        decoratedLifecycle
            // Keep the sidebar's "My Pads" row in sync with this list's "Mine"
            // preset: publish the live state (so the highlight is honest however
            // it changed — chip or sidebar) and consume any toggle the sidebar
            // queued. `initial: true` covers the value already set on appear.
            .onChange(of: mineOnly, initial: true) { _, isOn in publishMergedPadsMineOnly(isOn) }
            .onChange(of: nav.mergedPadsMineRequest, initial: true) { _, request in
                consumeMergedPadsMineRequest(request)
            }
            // The same publish/consume dance for the "Active Pads" preset, which the
            // sidebar drives through `stateFilter` rather than a dedicated flag.
            .onChange(of: stateFilter, initial: true) { _, state in publishMergedPadsActiveOnly(state == .active) }
            .onChange(of: nav.mergedPadsActiveRequest, initial: true) { _, request in
                consumeMergedPadsActiveRequest(request)
            }
            // A favourite pad tapped in the merged sidebar arrives here by id (pad ids
            // are globally unique, so no account need travel with it). Cleared once
            // consumed; left as the selection if the row hasn't loaded yet — the same
            // best-effort the per-account view uses.
            .onChange(of: router.pendingFavoritePadID) { _, id in
                guard let id else { return }

                router.pendingFavoritePadID = nil
                selectedIDs = [id]
            }
            // Consume navigation requests routed to Pads. In merged mode this includes
            // owner/search requests from person links as well as New Pad deep links;
            // `applyPendingRequest()` keeps those semantics aligned with `PadsView`.
            .onChange(of: nav.padsRequest, initial: true) { _, _ in scheduleApplyPendingRequest() }
            .onChange(of: selection) { _, newValue in
                // Debounced off the click's synchronous path: `markOpened` mutates the shared
                // Observable open-history store every row reads, so it rebuilds the whole
                // list. Only the pad you settle on (not every row arrowed past) is marked.
                if let newValue, let account = router.account(forPadID: newValue.id)?.id {
                    markOpenedTask?.cancel()
                    markOpenedTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }

                        openedStore.markOpened(newValue.id, account: account)
                    }
                }
                if selectedID != newValue?.id { selectedID = newValue?.id }
            }
    }

    private func publishMergedPadsMineOnly(_ isOn: Bool) {
        guard nav.mergedPadsMineOnly != isOn else { return }

        DispatchQueue.main.async {
            if nav.mergedPadsMineOnly != isOn { nav.mergedPadsMineOnly = isOn }
        }
    }

    private func consumeMergedPadsMineRequest(_ request: Bool?) {
        guard let request else { return }

        DispatchQueue.main.async {
            guard nav.mergedPadsMineRequest != nil else { return }

            nav.mergedPadsMineRequest = nil
            if mineOnly != request { mineOnly = request }
        }
    }

    private func publishMergedPadsActiveOnly(_ isOn: Bool) {
        guard nav.mergedPadsActiveOnly != isOn else { return }

        DispatchQueue.main.async {
            if nav.mergedPadsActiveOnly != isOn { nav.mergedPadsActiveOnly = isOn }
        }
    }

    private func consumeMergedPadsActiveRequest(_ request: Bool?) {
        guard let request else { return }

        DispatchQueue.main.async {
            guard nav.mergedPadsActiveRequest != nil else { return }

            nav.mergedPadsActiveRequest = nil
            // Turning it off only clears an Active filter — a different state the user
            // set by hand (e.g. Ended) is left untouched.
            let target: PadState? = request ? .active : (stateFilter == .active ? nil : stateFilter)
            if stateFilter != target { stateFilter = target }
        }
    }

    private func scheduleApplyPendingRequest() {
        DispatchQueue.main.async { applyPendingRequest() }
    }

    /// The reload / pad-update / pad-deletion router streams.
    var decoratedStreams: some View {
        decoratedSync
            .task {
                for await _ in AppRouter.reloads {
                    await reload()
                }
            }
            .task {
                for await updated in AppRouter.padUpdates {
                    applyUpdated(updated)
                }
            }
            .task {
                for await id in AppRouter.padDeletions {
                    // Drop the deleted id from the selection. If it was the primary,
                    // a neighbor (computed while the row is still present) takes over
                    // only when no other rows remain selected; otherwise the primary
                    // falls to a still-selected row via the `selectedIDs` observer.
                    let wasPrimary = selection?.id == id
                    let neighbor = wasPrimary ? neighborSelection(forDeleted: id) : nil
                    selectedIDs.remove(id)
                    removePad(id: id)
                    // Keep the disk cache, Spotlight index, and widget in step.
                    cache.removePad(id: id)
                    if wasPrimary, selectedIDs.isEmpty {
                        selectedIDs = neighbor.map { [$0.id] } ?? []
                    }
                }
            }
    }

    var content: some View {
        Group {
            if isLoading, scoped.isEmpty {
                ProgressView("Loading pads…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .id("loading")
            } else {
                VStack(spacing: 0) {
                    filterBar
                    errorBar
                    Divider()
                    padCollection
                }
                .transition(.opacity)
                .id("content")
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isLoading && scoped.isEmpty)
        // Surface the count beneath the "Pads" title in the window toolbar rather
        // than as an inline bar above the list.
        .reportsSectionCount(countSubtitle)
        .toolbar(id: "merged-pads") { padsToolbar }
    }

    /// The account a deep-link New Pad targets in merged mode: the current account
    /// when its key is usable, else the first mergeable account that has a key. Nil
    /// only when no account has a key, in which case the request is a no-op.
    var newPadDefaultAccount: Account? {
        if let current = accounts.currentAccount, !current.apiKey.isEmpty { return current }
        return accounts.mergeableAccounts.first { !$0.apiKey.isEmpty }
    }

    @ToolbarContentBuilder
    var padsToolbar: some CustomizableToolbarContent {
        // Hidden by default — reachable via View ▸ Customize Toolbar…, the
        // File ▸ Reload command (⌘R), or pull-to-refresh (#413).
        ToolbarItem(id: "reload", placement: .automatic) {
            ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
        }
        .defaultCustomization(.hidden)
        // Grouped beside Reload at the list column's leading edge rather than
        // floating at the trailing edge: a `.primaryAction` here shares the window's
        // trailing region with the detail pane's actions, so selecting a pad would
        // shove this button leftward. Anchoring it left keeps it put.
        ToolbarItem(id: "new-pad", placement: .automatic) {
            Menu {
                ForEach(accounts.mergeableAccounts) { account in
                    Button(account.name) { creatingForAccount = account }
                        .disabled(account.apiKey.isEmpty)
                }
            } label: {
                Label("New Pad", systemImage: "plus")
            }
            .disabled(isReadOnly)
            .help("Create a new pad in one of your accounts")
            .accessibilityLabel("New Pad")
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

    private var padCollection: some View {
        padList
            .overlay {
                if filtered.isEmpty, !scoped.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Pads", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("No pads match the current filters.")
                    }
                } else if scoped.isEmpty, !isLoading {
                    // Spell out that this account set is genuinely empty, so it doesn't
                    // read as still-loading or over-filtered (#618).
                    ContentUnavailableView {
                        Label("No Pads", systemImage: "doc.text")
                    } description: {
                        Text("Pads from your accounts will appear here once you create or join them.")
                    }
                }
            }
            .onKeyPress(.return) {
                guard let selection else { return .ignored }

                openPad(selection)
                return .handled
            }
            .macPullToRefresh { await reload() }
            .focusedSceneValue(\.focusedPad, selection)
        // Edit ▸ Copy / ⌘C copies the selected pads' web URLs (one per line)
        // while the list holds focus, matching the row's "Copy Pad URL" action
        // and extending it to a multi-row selection. The O(N) `selectedPadsInOrder`
        // scan is built lazily (only on an actual copy); the per-render gate is the
        // O(1) empty-selection check, so it stays off the click path.
        #if os(macOS)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedIDs.isEmpty) {
                selectedPadsInOrder.map(\.url).joined(separator: "\n")
            })
        #endif
    }

    /// The selected pads in the order they appear in the list (rather than the
    /// selection set's arbitrary order), so a multi-row Copy or Delete reads top to
    /// bottom. Resolved against `filtered` — the rows the user can actually see.
    var selectedPadsInOrder: [Pad] {
        filtered.compactMap { selectedIDs.contains($0.item.id) ? $0.item : nil }
    }

    private var padList: some View {
        // NSTableView-backed (#439): recycles only visible rows, so selection is
        // instant on large combined lists — see `FastList` and the pads list.
        FastList(filtered, selection: $selectedIDs) { row in
            PadRowHostableContent(
                pad: row.item,
                isChanged: PadListLogic.hasNewActivitySinceOpen(
                    row.item, lastOpened: openedStore.lastOpened(row.item.id, account: row.account.id)
                ),
                rowAccount: RowAccount(row.account),
                ownerDisplay: directory.display(row.item.ownerEmail),
                isFavorite: favoritePads.isFavorite(row.item.id, account: row.account.id),
                onToggleFavorite: {
                    favoritePads.toggle(row.item.id, title: row.item.title, account: row.account.id,
                                        undoManager: undoManager)
                }
            )
            .fastListRowManualSelection(id: row.item.id, selection: $selectedIDs)
            // iPad: drag onto the sidebar Favorites to pin, or out to Safari/Notes/Split View.
            .favoriteDraggable(padFavoritePayload(row), title: row.item.title.isEmpty ? row.item.id : row.item.title)
            // iPad: the row's context menu with a compact preview (macOS uses the FastList
            // `NSMenu` path below instead).
            .favoriteRowContextMenu(padTableMenuItems(row),
                                    title: row.item.title.isEmpty ? row.item.id : row.item.title)
        }
        #if os(macOS)
        .rowHeight(FastListRowMetrics.macHeight)
        #endif
        .reloadID(mergedPadListReloadID)
        // Double-click opens the pad's native detail in its own window with the
        // originating account (#354); Return opens its live URL in the browser.
        .onDoubleClick { row in
            openWindow(id: "pad", value: PadWindowID(account: row.account.id, id: row.item.id))
        }
        .onReturnKey { openPad($0.item) }
        .swipeActions(edge: .leading) { row in
            let starred = favoritePads.isFavorite(row.item.id, account: row.account.id)
            return [SwipeAction(
                title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                tint: Color(platformColor: .systemYellow),
                systemImage: starred ? "star.slash" : "star.fill"
            ) {
                favoritePads.toggle(row.item.id, title: row.item.title, account: row.account.id,
                                    undoManager: undoManager)
            }]
        }
        .swipeActions(edge: .trailing) { row in
            isReadOnly ? [] : [SwipeAction(title: String(localized: "Delete"), role: .destructive,
                                           systemImage: "trash") {
                    padPendingDelete = row.item
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
    }

    private var mergedPadListReloadID: String {
        accounts.mergeableAccounts
            .map { account in
                "\(account.id.uuidString):\(favoritePads.favorites(account: account.id).joined(separator: ","))"
            }
            .joined(separator: "|")
    }
}
