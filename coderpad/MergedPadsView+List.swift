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
                await periodicReload(interval: { GeneralSettings.refreshInterval }, work: {
                    await reload()
                })
            }
            .onAppear { selectedID = selection?.id }
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
            .onChange(of: selectedID) { _, newID in
                if selection?.id != newID {
                    selection = newID.flatMap { id in pad(forID: id) }
                }
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
                    if selection?.id == id { selection = neighborSelection(forDeleted: id) }
                    removePad(id: id)
                    // Keep the disk cache, Spotlight index, and widget in step.
                    cache.removePad(id: id)
                }
            }
            // Mirror the toolbar's Bulk menu: the Pad menu's bulk commands post
            // these, and either pads pane (this one or the single-account view)
            // runs them through the same confirmation it already shows.
            .task {
                for await _ in AppRouter.bulkEndStartedRequests {
                    bulkAction = .endStarted
                }
            }
            .task {
                for await _ in AppRouter.bulkMakePrivateRequests {
                    bulkAction = .makePrivate
                }
            }
            .sheet(item: $creatingForAccount) { account in
                NewPadSheet(client: account.makeClient()) { created in
                    insert(created, into: account)
                    selection = created
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
            .alert("Couldn't delete pad",
                   isPresented: .init(get: { deleteError != nil },
                                      set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
            .confirmationDialog(
                bulkConfirmTitle,
                isPresented: .init(get: { bulkAction != nil },
                                   set: { if !$0 { bulkAction = nil } }),
                titleVisibility: .visible,
                presenting: bulkAction
            ) { action in
                Button(bulkConfirmButton(action), role: .destructive) {
                    Task { await performBulk(action) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(bulkConfirmMessage(action))
            }
            .alert("Some pads couldn't be updated",
                   isPresented: .init(get: { bulkError != nil },
                                      set: { if !$0 { bulkError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bulkError ?? "")
            }
    }

    var content: some View {
        Group {
            if isLoading, scoped.isEmpty {
                ProgressView("Loading pads…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    PaneTitle(title: "Pads")
                    presetsBar
                    filterBar
                    resultCountBar
                    errorBar
                    Divider()
                    padCollection
                }
            }
        }
        .toolbar(id: "pads.toolbar") { padsToolbar }
    }

    @ToolbarContentBuilder
    var padsToolbar: some CustomizableToolbarContent {
        ToolbarItem(id: "reload") {
            ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
        }
        ToolbarItem(id: "new", placement: .primaryAction) {
            Menu {
                ForEach(accounts.mergeableAccounts) { account in
                    Button(account.name) { creatingForAccount = account }
                        .disabled(account.apiKey.isEmpty)
                }
            } label: {
                Label("New Pad", systemImage: "plus")
            }
            .help("Create a new pad in one of your accounts")
            .accessibilityLabel("New Pad")
        }
        ToolbarItem(id: "bulk") {
            Menu {
                Button("End Started Pads…", systemImage: "flag.checkered") {
                    bulkAction = .endStarted
                }
                .disabled(PadListLogic.startedPads(in: filtered.map(\.item)).isEmpty)
                Button("Make Visible Pads Private…", systemImage: "lock") {
                    bulkAction = .makePrivate
                }
                .disabled(PadListLogic.nonPrivatePads(in: filtered.map(\.item)).isEmpty)
            } label: {
                Label("Bulk Actions", systemImage: "ellipsis.circle")
            }
            .help("Apply an action to all pads currently shown in the list")
            .disabled(filtered.isEmpty || isBulkRunning)
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
            .focusedSceneValue(\.padBulkAvailability, PadBulkAvailability(
                canEndStarted: !isBulkRunning && !PadListLogic.startedPads(in: filtered.map(\.item)).isEmpty,
                canMakePrivate: !isBulkRunning && !PadListLogic.nonPrivatePads(in: filtered.map(\.item)).isEmpty
            ))
    }

    private var padList: some View {
        List(selection: $selectedID) {
            ForEach(filtered) { row in
                padRow(row)
                    .tag(row.item.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            padPendingDelete = row.item
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
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
            accountName: row.account.name
        )
        .contextMenu { padContextMenu(row) }
    }

    @ViewBuilder
    private func padContextMenu(_ row: AccountScoped<Pad>) -> some View {
        Button {
            selection = row.item
            openPad(row.item)
        } label: {
            Label("Open Pad", systemImage: "doc.text.image")
        }
        if let url = row.item.webURL {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button { copyToPasteboard(row.item.id) } label: {
            Label("Copy Pad ID", systemImage: "number")
        }
        Button { copyToPasteboard(row.item.url) } label: {
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
    }
}
