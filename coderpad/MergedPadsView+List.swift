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
import FastList
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
                // A favourite tapped before the list loaded parked its bare slug;
                // resolve it to a namespaced row id now that rows may exist (#758).
                resolvePendingSlugSelection()
                // Initial load, then refresh on the fixed app cadence.
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
                // Restore the filters the list was left with last session; any queued
                // navigation request is consumed by the focus-gated observer (which
                // also runs on appear), so person links can still override the
                // restored owner/search fields while preserving the rest.
                restoreFilters()
                // Prefer the row in the account the selection was made in (tracked
                // by the router): pad slugs are only unique per server, so the bare
                // slug can otherwise re-select a different account's same-slug row (#758).
                let restored = selection.flatMap { sel in
                    scoped.first { $0.item.id == sel.id && $0.account.id == router.selectedPadAccountID }
                        ?? scoped.first { $0.item.id == sel.id }
                }
                selectedIDs = restored.map { [$0.id] } ?? []
            }
            .onChange(of: cache.padsByAccount) { _, _ in hydrateFromCacheIfEmpty() }
            // Re-persist whenever any filter changes; `filterSignature` shifts for
            // every filter control, so one observer covers them all.
            .onChange(of: filterSignature) { _, _ in persistFilters() }
            .task(id: dateFilterClockActive) { await runDateFilterClock() }
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
                // `selectRow` also publishes the row's source account so the detail pane
                // routes to the right client when two servers share a pad slug (#758).
                selectRow(primary)
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
            // Focus-gated (#910): a background window's merged list must not steal
            // a toggle aimed at the focused one.
            .consumesWindowRequest(nav.mergedPadsMineRequest) {
                consumeMergedPadsMineRequest(nav.mergedPadsMineRequest)
            }
            // The same publish/consume dance for the "Active Pads" preset, which the
            // sidebar drives through `stateFilter` rather than a dedicated flag.
            .onChange(of: stateFilter, initial: true) { _, state in publishMergedPadsActiveOnly(state == .active) }
            .consumesWindowRequest(nav.mergedPadsActiveRequest) {
                consumeMergedPadsActiveRequest(nav.mergedPadsActiveRequest)
            }
            // A favourite pad tapped in the merged sidebar arrives here with its
            // account: pad slugs are only unique per server, so the slug alone could
            // select a different account's same-slug row (#758). Cleared once
            // consumed; left untouched if the row hasn't loaded yet (the row id
            // simply won't resolve, the same best-effort the per-account view uses).
            // Focus-gated and attempted on appear: the tap can also switch the
            // section, so the pending favourite is set before this list mounts and
            // a change-only observer would drop it (#1016). Scroll the row into
            // view too - the selection alone can land off-screen in a long list (#1019).
            .consumesWindowRequest(nav.pendingMergedFavoritePad) {
                guard let request = nav.pendingMergedFavoritePad else { return }

                nav.pendingMergedFavoritePad = nil
                let rowID = Self.rowID(account: request.account, pad: request.id)
                selectedIDs = [rowID]
                pendingScrollToID = rowID
            }
            // Consume navigation requests routed to Pads. In merged mode this includes
            // owner/search requests from person links as well as New Pad deep links;
            // `applyPendingRequest()` keeps those semantics aligned with `PadsView`.
            // Focus-gated so a background window's list can't steal them (#910).
            .consumesWindowRequest(nav.padsRequest) { applyPendingRequest() }
            .onChange(of: selection) { _, newValue in
                // Debounced off the click's synchronous path: `markOpened` mutates the shared
                // Observable open-history store every row reads, so it rebuilds the whole
                // list. Only the pad you settle on (not every row arrowed past) is marked.
                // The account comes from the router's selected-pad account (published by
                // `selectRow`), falling back to the route map: two custom servers can share
                // a slug, so the map alone can point at the wrong account (#758).
                guard let newValue else {
                    if selectedID != nil { selectedID = nil }
                    return
                }
                let account = router.selectedPadAccountID ?? router.account(forPadID: newValue.id)?.id
                guard let account else { return }

                // A selection restored from the last session must not be re-marked
                // opened, or a pad that changed while the app was closed would lose
                // its "new activity" dot before being seen (#1043). Consumed once,
                // mirroring `PadsView`.
                if isRestoringSelection {
                    isRestoringSelection = false
                } else {
                    markOpenedTask?.cancel()
                    markOpenedTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        guard !Task.isCancelled else { return }

                        openedStore.markOpened(newValue.id, account: account)
                    }
                }
                // Keep the primary row id in step when the selection was set from
                // outside the list; compare namespaced row ids, never bare slugs (#758).
                let rowID = Self.rowID(account: account, pad: newValue.id)
                if selectedID != rowID { selectedID = rowID }
            }
    }

    private func publishMergedPadsMineOnly(_ isOn: Bool) {
        let windowNav = windowNav
        guard windowNav.mergedPadsMineOnly != isOn else { return }

        DispatchQueue.main.async {
            if windowNav.mergedPadsMineOnly != isOn { windowNav.mergedPadsMineOnly = isOn }
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
        let windowNav = windowNav
        guard windowNav.mergedPadsActiveOnly != isOn else { return }

        DispatchQueue.main.async {
            if windowNav.mergedPadsActiveOnly != isOn { windowNav.mergedPadsActiveOnly = isOn }
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

    /// The reload / pad-update / pad-deletion router streams.
    var decoratedStreams: some View {
        decoratedSync
            .onReloadRequest { await reload() }
            .task {
                for await mutation in AppRouter.padUpdates {
                    applyUpdated(mutation.pad, account: mutation.account)
                }
            }
            .task {
                for await creation in AppRouter.padCreations {
                    applyCreated(creation)
                }
            }
            .task {
                for await deletion in AppRouter.padDeletions {
                    // Drop every selected row whose pad matches the deleted slug,
                    // scoped to the owning account when the broadcast carries one so a
                    // colliding slug on another custom server keeps its row (#761). If
                    // the primary was among them, a neighbor - computed while the row
                    // is still present - takes over only when no other rows remain
                    // selected; otherwise the primary falls to a still-selected row
                    // via the `selectedIDs` observer.
                    let id = deletion.id
                    let removed = selectedIDs.filter { rowID in
                        guard let row = row(forRowID: rowID), row.item.id == id else { return false }

                        return deletion.account == nil || row.account.id == deletion.account
                    }
                    let wasPrimary = selectedID.map { removed.contains($0) } ?? false
                    let neighbor = wasPrimary
                        ? selectedID.flatMap { neighborRowID(forDeletedRowID: $0) } : nil
                    selectedIDs.subtract(removed)
                    removePad(id: id, account: deletion.account)
                    // Keep the disk cache, Spotlight index, and widget in step.
                    cache.removePad(id: id, account: deletion.account)
                    if wasPrimary, selectedIDs.isEmpty {
                        selectedIDs = neighbor.map { [$0] } ?? []
                    }
                }
            }
    }

    var content: some View {
        VStack(spacing: 0) {
            filterBar
            errorBar
            Divider()
            padCollection
        }
        .transition(.opacity)
        .id("content")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isLoading && !scoped.isEmpty)
        // Surface the count beneath the "Pads" title in the window toolbar rather
        // than as an inline bar above the list.
        .reportsSectionCount(countSubtitle)
        .toolbar(id: "merged-pads") { padsToolbar }
    }

    private var padCollection: some View {
        padList
            .overlay {
                if filtered.isEmpty, !scoped.isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Pads", systemImage: "line.3.horizontal.decrease.circle")
                    } actions: {
                        Button("Clear Filters") { clearAllFilters() }
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
        // and extending it to a multi-row selection. The O(N) `selectedRowsInOrder`
        // scan is built lazily (only on an actual copy); the per-render gate is the
        // O(1) empty-selection check, so it stays off the click path.
        #if os(macOS)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedIDs.isEmpty) {
                selectedRowsInOrder.map(\.item.url).joined(separator: "\n")
            })
        #endif
    }

    /// The selected rows in the order they appear in the list (rather than the
    /// selection set's arbitrary order), so a multi-row Copy or Delete reads top to
    /// bottom. Rows rather than bare `Pad`s so each carries its source account for
    /// per-account routing (#758). Resolved against `filtered` — the rows the user
    /// can actually see.
    var selectedRowsInOrder: [AccountScoped<Account, Pad>] {
        filtered.filter { selectedIDs.contains($0.id) }
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
            .fastListRowManualSelection(id: row.id, selection: $selectedIDs)
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
                    padPendingDelete = row
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
