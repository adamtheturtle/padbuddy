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
    var decorated: some View {
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
                // Double-clicking a row opens the selected pad (the first click
                // selects it). Reads `selection` live, so it stays correct.
                doubleClickProxy.onDoubleClick = { openSelectedPadInWindow() }
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
            }
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
            .onChange(of: selectedID) { _, newID in
                if selection?.id != newID {
                    selection = newID.flatMap { id in pad(forID: id) }
                }
                // Remember the open pad so the merged list reopens to it next launch.
                persistSelectedPad()
            }
            .onChange(of: selection) { _, newValue in
                if let newValue, let account = router.account(forPadID: newValue.id)?.id {
                    openedStore.markOpened(newValue.id, account: account)
                }
                if selectedID != newValue?.id { selectedID = newValue?.id }
            }
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
            .sheet(item: $creatingForAccount) { account in
                NewPadSheet(client: account.makeClient()) { created in
                    insert(created, into: account)
                    selectedIDs = [created.id]
                    creatingForAccount = nil
                } onCancel: {
                    creatingForAccount = nil
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
                    Task { for pad in pads { await deletePad(pad) } }
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

    @ToolbarContentBuilder
    var padsToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "reload", placement: .automatic) {
            ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
        }
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
            // and extending it to a multi-row selection.
            .onCopyCommand(perform: copyLinkCommand(
                selectedPadsInOrder.isEmpty ? nil
                    : selectedPadsInOrder.map(\.url).joined(separator: "\n")
            ))
    }

    /// The selected pads in the order they appear in the list (rather than the
    /// selection set's arbitrary order), so a multi-row Copy or Delete reads top to
    /// bottom. Resolved against `filtered` — the rows the user can actually see.
    private var selectedPadsInOrder: [Pad] {
        filtered.compactMap { selectedIDs.contains($0.item.id) ? $0.item : nil }
    }

    private var padList: some View {
        // Wrap in a reader so a restored selection can be scrolled into view on
        // launch (see `pendingScrollToID`); the reader sits outside the `.id` below
        // so its proxy survives the filter-driven list rebuilds.
        ScrollViewReader { proxy in
            padListBody
                // Scroll the restored pad into view once, then clear the request so
                // the user's own scrolling afterward is never overridden.
                .onChange(of: pendingScrollToID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id, anchor: .center)
                    pendingScrollToID = nil
                }
        }
    }

    private var padListBody: some View {
        List(selection: $selectedIDs) {
            ForEach(filtered) { row in
                padRow(row)
                    .tag(row.item.id)
                    .installsTableDoubleClick(doubleClickProxy)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            padPendingDelete = row.item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(isReadOnly)
                    }
            }
        }
        .listStyle(.inset)
        .id(filterSignature)
        .transaction { $0.animation = nil }
    }

    private func padRow(_ row: AccountScoped<Pad>) -> some View {
        PadRow(
            pad: row.item,
            isChanged: PadListLogic.hasNewActivitySinceOpen(
                row.item, lastOpened: openedStore.lastOpened(row.item.id, account: row.account.id)
            ),
            accountName: row.account.name,
            account: row.account.id
        )
        .contextMenu { padContextMenu(row) }
    }

    /// Opens the selected pad's live URL in a window on double-click, honoring the
    /// "Open links" preference — the in-app `pad-browser` window or the external
    /// browser — exactly as the row's old gesture and the detail "Open" button do.
    func openSelectedPadInWindow() {
        guard let url = selection?.webURL else { return }
        if BrowserSettings.openLinksIn == .external {
            BrowserSettings.openExternally(url)
        } else {
            openWindow(id: "pad-browser", value: url)
        }
    }

    @ViewBuilder
    private func padContextMenu(_ row: AccountScoped<Pad>) -> some View {
        // Right-clicking a row that's part of a multi-row selection acts on the whole
        // selection, the way Finder does; otherwise it's the usual single-row menu.
        if selectedIDs.count > 1, selectedIDs.contains(row.item.id) {
            bulkContextMenu
        } else {
            Button {
                selectedIDs = [row.item.id]
                openPad(row.item)
            } label: {
                Label("Open Pad", systemImage: "doc.text.image")
            }
            if let url = row.item.webURL {
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
            }
            Divider()
            Button { Clipboard.copy(row.item.id) } label: {
                Label("Copy Pad ID", systemImage: "number")
            }
            Button { Clipboard.copy(row.item.url) } label: {
                Label("Copy Pad URL", systemImage: "link")
            }
            Divider()
            Button { accountFilter = row.account.id } label: {
                Label("Show Only \(row.account.name)", systemImage: "person.crop.circle")
            }
            Button { ownerFilter = row.item.ownerEmail } label: {
                Label("Show Pads from \(directory.display(row.item.ownerEmail))", systemImage: "person")
            }
            Divider()
            Button(role: .destructive) {
                padPendingDelete = row.item
            } label: {
                Label("Delete…", systemImage: "trash")
            }
            .disabled(isReadOnly)
        }
    }

    /// The actions offered when right-clicking inside a multi-row selection: copy
    /// every selected pad's link at once, or delete them all (behind a confirmation).
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
}
