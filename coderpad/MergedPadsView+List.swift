//
//  MergedPadsView+List.swift
//  coderpad
//
//  The view body, list, rows, and lifecycle/dialog modifiers for the combined
//  pads list. Kept out of the primary struct so its body-length stays small.
//

import AppKit
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
                await periodicReload(interval: { GeneralSettings.refreshInterval }, work: {
                    await reload()
                })
            }
            .onAppear {
                // Restore the filters the list was left with last session before
                // bridging the selection, so the list opens in the same view.
                restoreFilters()
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
            .onChange(of: mineOnly, initial: true) { _, isOn in
                if nav.mergedPadsMineOnly != isOn { nav.mergedPadsMineOnly = isOn }
            }
            .onChange(of: nav.mergedPadsMineRequest, initial: true) { _, request in
                guard let request else { return }

                nav.mergedPadsMineRequest = nil
                if mineOnly != request { mineOnly = request }
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
            // Consume a New Pad request routed here (widget/Dock/Control Center/menu
            // ⌘N deep links all funnel through `coderpad://new-pad` → `showPads`).
            // The single-account `PadsView` owns search/owner/saved-search requests;
            // merged mode only needs the create case, which it had been silently
            // dropping — the New Pad button did nothing while "All Accounts" was on
            // (#456). Creation is inherently single-account, so seed the current
            // account's sheet (a link that pinned an account already left merged mode
            // in `handleDeepLink`). `initial: true` covers a request queued before
            // this list mounted, e.g. from a cold launch.
            .onChange(of: nav.padsRequest, initial: true) { _, request in
                guard let request, request.startCreating, !isReadOnly else { return }

                nav.padsRequest = nil
                creatingSeedQuestionID = request.seedQuestionID
                creatingForAccount = newPadDefaultAccount
            }
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

    /// The reload / pad-update / pad-deletion router streams.
    private var decoratedStreams: some View {
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

    /// The new-pad sheet, delete confirmations, and delete-error alert.
    private var decoratedDialogs: some View {
        decoratedStreams
            .sheet(item: $creatingForAccount) { account in
                NewPadSheet(client: account.makeClient(), initialQuestionID: creatingSeedQuestionID) { created in
                    insert(created, into: account)
                    selectedIDs = [created.id]
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                } onCancel: {
                    creatingForAccount = nil
                    creatingSeedQuestionID = nil
                }
            }
            .confirmationDialog(
                "Delete this pad?",
                isPresented: .init(get: { padPendingDelete != nil },
                                   set: { if !$0 { padPendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: padPendingDelete
            ) { pad in
                Button("Delete Pad", role: .destructive) { Task { await deletePad(pad) } }
                Button("Cancel", role: .cancel) {}
            } message: { pad in
                Text("“\(pad.title)” will be permanently deleted. This can't be undone.")
            }
            .confirmationDialog(
                "Delete \(padsPendingBulkDelete?.count ?? 0) pads?",
                isPresented: .init(get: { padsPendingBulkDelete != nil },
                                   set: { if !$0 { padsPendingBulkDelete = nil } }),
                titleVisibility: .visible,
                presenting: padsPendingBulkDelete
            ) { pads in
                Button("Delete \(pads.count) Pads", role: .destructive) {
                    Task { for pad in pads {
                        await deletePad(pad)
                    } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pads in
                Text("These \(pads.count) pads will be permanently deleted. This can't be undone.")
            }
            .alert("Couldn't delete pad",
                   isPresented: .init(get: { deleteError != nil },
                                      set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
    }

    var content: some View {
        Group {
            if isLoading, scoped.isEmpty {
                ProgressView("Loading pads…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    presetsBar
                    filterBar
                    errorBar
                    Divider()
                    padCollection
                }
            }
        }
        // Surface the count beneath the "Pads" title in the window toolbar rather
        // than as an inline bar above the list.
        .reportsSectionCount(countSubtitle)
        .toolbar(id: "merged-pads") { padsToolbar }
    }

    /// The account a deep-link New Pad targets in merged mode: the current account
    /// when its key is usable, else the first mergeable account that has a key. Nil
    /// only when no account has a key, in which case the request is a no-op.
    private var newPadDefaultAccount: Account? {
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
                    } actions: {
                        Button("Clear Filters") { clearAllFilters() }
                    }
                } else if scoped.isEmpty, !isLoading {
                    ContentUnavailableView("No Pads", systemImage: "doc.text")
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
            .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedIDs.isEmpty) {
                selectedPadsInOrder.map(\.url).joined(separator: "\n")
            })
    }

    /// The selected pads in the order they appear in the list (rather than the
    /// selection set's arbitrary order), so a multi-row Copy or Delete reads top to
    /// bottom. Resolved against `filtered` — the rows the user can actually see.
    var selectedPadsInOrder: [Pad] {
        filtered.compactMap { selectedIDs.contains($0.item.id) ? $0.item : nil }
    }

    private var padList: some View {
        // NSTableView-backed (#439): recycles only visible rows, so selection is
        // instant on large combined lists — see `ListTable` and the pads list.
        ListTable(
            items: filtered,
            selection: $selectedIDs,
            scrollToID: pendingScrollToID,
            onScrolledToID: { pendingScrollToID = nil },
            rowContent: { row in
                AnyView(PadRowHostableContent(
                    pad: row.item,
                    isChanged: PadListLogic.hasNewActivitySinceOpen(
                        row.item, lastOpened: openedStore.lastOpened(row.item.id, account: row.account.id)
                    ),
                    accountName: row.account.name,
                    ownerDisplay: directory.display(row.item.ownerEmail),
                    account: row.account.id,
                    favoritePads: favoritePads
                ))
            },
            // Double-click opens the pad's native detail in its own window with the
            // originating account (#354); Return opens its live URL in the browser.
            onDoubleClick: { row in
                openWindow(id: "pad", value: PadWindowID(account: row.account.id, id: row.item.id))
            },
            onReturn: { openPad($0.item) },
            leadingActions: { row in
                let starred = favoritePads.isFavorite(row.item.id, account: row.account.id)
                return [RowSwipeAction(
                    title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                    tint: .systemYellow,
                    systemImage: starred ? "star.slash" : "star.fill"
                ) { favoritePads.toggle(row.item.id, account: row.account.id) }]
            },
            trailingActions: { row in
                isReadOnly ? [] : [RowSwipeAction(title: String(localized: "Delete"), isDestructive: true,
                                                  systemImage: "trash") {
                        padPendingDelete = row.item
                    }]
            },
            pasteboardItem: { padPasteboardItem($0) },
            menuItems: { padTableMenuItems($0) },
            onTopRowChange: { persistTopRow($0) },
            onDragSessionBegan: FavoriteDragLifecycle.onBegan,
            onDragSessionEnded: FavoriteDragLifecycle.onEnded
        )
    }
}
