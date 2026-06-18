//
//  MergedQuestionsView+List.swift
//  coderpad
//
//  The view body, list, rows, and lifecycle modifiers for the combined questions
//  list. Kept out of the primary struct so its body-length stays small.
//

import AppKit
import SwiftUI

extension MergedQuestionsView {
    /// Split across several intermediate `some View` properties rather than one long
    /// modifier chain: a single ~13-modifier chain makes the Swift type-checker infer one
    /// deeply-nested generic type and blows the Release build's 250ms type-check-timing
    /// budget (warnings-as-errors). Each sub-chain type-checks independently. Order is
    /// preserved. (#427)
    var decorated: some View {
        decoratedDialogs
    }

    private var decoratedLifecycle: some View {
        content
            .task(id: QuestionsTaskKey(apiKey: accountKey, phase: scenePhase)) {
                guard scenePhase == .active else { return }

                seedFromCache()
                // Reopen the question selected last session, once the seeded cache (or
                // the reload below) provides a list to resolve it against.
                restoreSelectedRowIfNeeded()
                await periodicReload(interval: { GeneralSettings.refreshInterval }, work: {
                    await reload()
                })
            }
            .onAppear {
                // Restore the filters the list was left with last session before
                // bridging the selection, so the list opens in the same view.
                restoreFilters()
                selectedRowIDs = selection
                    .flatMap { sel in scoped.first { $0.item.id == sel.id }?.id }
                    .map { [$0] } ?? []
            }
            // Re-persist whenever any filter changes; `filterSignature` shifts for
            // every filter control, so one observer covers them all.
            .onChange(of: filterSignature) { _, _ in persistFilters() }
            // The List edits `selectedRowIDs`; derive the primary row from it so the
            // detail pane and routing keep working off the single `selectedRowID`.
            // One-way (set → primary), so there's no two-way binding loop.
            .onChange(of: selectedRowIDs) { previous, current in
                let primary = MultiSelectLogic.primaryID(previous: previous, current: current)
                if selectedRowID != primary { selectedRowID = primary }
                // Bridge to the detail-pane selection and persist in the same pass rather
                // than via a separate `onChange(selectedRowID)`: each extra state write
                // re-runs `body` and rebuilds the list's prepared rows, so collapsing the
                // cascade removes a full rebuild per click on a large list (PadsView fix).
                selectRow(primary)
                Task { @MainActor in persistSelectedRow() }
            }
    }

    private var decoratedSync: some View {
        decoratedLifecycle
            // A favourite tapped in the merged sidebar arrives here with its account,
            // so it selects the right row even when two orgs share a per-org id. Cleared
            // once consumed; left untouched if the row hasn't loaded yet (the row id
            // simply won't resolve, the same best-effort the per-account view uses).
            .onChange(of: router.pendingFavoriteQuestion) { _, request in
                guard let request else { return }

                router.pendingFavoriteQuestion = nil
                selectedRowIDs = [Self.rowID(account: request.account, question: request.id)]
            }
            // Keep the sidebar's "My Questions" row in sync with this list's "Mine"
            // preset: publish the live state and consume any sidebar toggle, the
            // same bridge `MergedPadsView` uses for "My Pads".
            .onChange(of: mineOnly, initial: true) { _, isOn in
                if nav.mergedQuestionsMineOnly != isOn { nav.mergedQuestionsMineOnly = isOn }
            }
            .onChange(of: nav.mergedQuestionsMineRequest, initial: true) { _, request in
                guard let request else { return }

                nav.mergedQuestionsMineRequest = nil
                if mineOnly != request { mineOnly = request }
            }
    }

    private var decoratedStreams: some View {
        decoratedSync
            .task {
                for await update in AppRouter.questionUpdates {
                    applyUpdated(update.question, account: update.account)
                }
            }
            .task {
                for await deletion in AppRouter.questionDeletions {
                    let id = deletion.id
                    let account = deletion.account
                    // Drop every selected row matching the deleted question (matched by
                    // account too, since per-org ids collide). If the primary was among
                    // them, move to a neighbor — computed while `sorted` still holds the
                    // row — but only when no other rows remain selected.
                    let removed = selectedRowIDs.filter { rowID in
                        guard let row = row(forRowID: rowID) else { return false }

                        return row.item.id == id && (account == nil || row.account.id == account)
                    }
                    let primaryDeleted = selectedRowID.map { removed.contains($0) } ?? false
                    let neighbor = primaryDeleted
                        ? selectedRowID.flatMap { neighborRowID(forDeletedRowID: $0) } : nil
                    selectedRowIDs.subtract(removed)
                    removeQuestion(id: id, account: account)
                    // Keep the disk cache and Spotlight index in step.
                    cache.removeQuestion(id: id, account: account)
                    if primaryDeleted, selectedRowIDs.isEmpty {
                        selectedRowIDs = neighbor.map { [$0] } ?? []
                    }
                }
            }
            .task {
                for await _ in AppRouter.reloads {
                    await reload()
                }
            }
    }

    private var decoratedDialogs: some View {
        decoratedStreams
            .sheet(item: $creatingForAccount) { account in
                NewQuestionSheet(client: account.makeClient()) { created in
                    insert(created, into: account)
                    let rowID = Self.rowID(account: account.id, question: created.id)
                    select(AccountScoped(account: account, item: created, id: rowID))
                    selectedRowIDs = [rowID]
                    creatingForAccount = nil
                } onCancel: {
                    creatingForAccount = nil
                }
            }
            .confirmationDialog(
                "Delete \(rowsPendingBulkDelete?.count ?? 0) questions?",
                isPresented: .init(get: { rowsPendingBulkDelete != nil },
                                   set: { if !$0 { rowsPendingBulkDelete = nil } }),
                titleVisibility: .visible,
                presenting: rowsPendingBulkDelete
            ) { rows in
                Button("Delete \(rows.count) Questions", role: .destructive) {
                    Task { await bulkDelete(rows) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { rows in
                Text("These \(rows.count) questions will be permanently deleted. This can't be undone.")
            }
            .alert("Couldn't delete question",
                   isPresented: .init(get: { bulkDeleteError != nil },
                                      set: { if !$0 { bulkDeleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bulkDeleteError ?? "")
            }
    }

    var content: some View {
        Group {
            if isLoading, scoped.isEmpty {
                ProgressView("Loading questions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    presetsBar
                    filterBar
                    errorBar
                    Divider()
                    questionsList
                }
            }
        }
        // Surface the count beneath the "Questions" title in the window toolbar
        // rather than as an inline bar above the list.
        .reportsSectionCount(countSubtitle)
        .toolbar(id: "merged-questions") { questionsToolbar }
    }

    @ToolbarContentBuilder
    var questionsToolbar: some CustomizableToolbarContent {
        // Hidden by default — reachable via View ▸ Customize Toolbar…, the
        // File ▸ Reload command (⌘R), or pull-to-refresh (#413).
        ToolbarItem(id: "reload", placement: .automatic) {
            ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
        }
        .defaultCustomization(.hidden)
        // Grouped beside Reload at the list column's leading edge rather than
        // floating at the trailing edge: a `.primaryAction` here shares the window's
        // trailing region with the detail pane's actions, so selecting a question
        // would shove this button leftward. Anchoring it left keeps it put.
        ToolbarItem(id: "new-question", placement: .automatic) {
            Menu {
                ForEach(accounts.mergeableAccounts) { account in
                    Button(account.name) { creatingForAccount = account }
                        .disabled(account.apiKey.isEmpty)
                }
            } label: {
                Label("New Question", systemImage: "plus")
            }
            .disabled(isReadOnly)
            .help("Create a new question in one of your accounts")
            .accessibilityLabel("New Question")
        }
        ToolbarItem(id: "sort", placement: .automatic) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(QuestionSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort questions")
            .accessibilityLabel("Sort questions")
        }
        // Opt-in detail-pane toggle, hidden by default (#404).
        DetailPaneToggleToolbarContent()
    }

    private var questionsList: some View {
        // NSTableView-backed (#439): recycles only visible rows, so selection is
        // instant on large combined lists — see `ListTable`.
        ListTable(
            items: sorted,
            selection: $selectedRowIDs,
            scrollToID: pendingScrollToRowID,
            onScrolledToID: { pendingScrollToRowID = nil },
            rowContent: { row in
                AnyView(QuestionRowHostableContent(
                    question: row.item,
                    accountName: row.account.name,
                    account: row.account.id,
                    favorites: favorites,
                    onToggleFavorite: { toggleFavorite(row) }
                ))
            },
            // Double-click / Return open the question in its own window with the
            // originating account (the first click selects it).
            onDoubleClick: { openQuestionWindow($0) },
            onReturn: { openQuestionWindow($0) },
            leadingActions: { row in
                let starred = isFavorite(row)
                return [RowSwipeAction(
                    title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                    tint: .systemYellow
                ) { toggleFavorite(row) }]
            },
            trailingActions: { row in
                guard !isReadOnly else { return [] }

                // Same path as the context-menu "Delete Question…": select the row,
                // then let its detail pane run the undoable delete.
                return [RowSwipeAction(title: String(localized: "Delete"), isDestructive: true) {
                    select(row)
                    nav.deleteQuestionID = row.item.id
                }]
            },
            pasteboardItem: { questionPasteboardItem($0) },
            menuItems: { questionTableMenuItems($0) }
        )
        .overlay { questionsOverlay }
        .macPullToRefresh { await reload() }
        .focusedSceneValue(\.focusedQuestion, selection)
        // Edit ▸ Copy / ⌘C copies the selected questions' web URLs (one per line)
        // while the list holds focus, matching the row's "Copy Question URL" action
        // and extending it to a multi-row selection. Each link is built from its
        // originating account's server URL, so a merged-list copy honors custom domains.
        // The O(N) `selectedQuestionURLsInOrder` scan is built lazily (only on an actual
        // copy); the per-render gate is the O(1) empty-selection check, off the click path.
        .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedRowIDs.isEmpty) {
            selectedQuestionURLsInOrder.joined(separator: "\n")
        })
    }

    /// Opens a combined-list question in its own window with its originating account.
    private func openQuestionWindow(_ row: AccountScoped<Question>) {
        openWindow(id: "question", value: QuestionWindowID(account: row.account.id, id: row.item.id))
    }

    /// The selected questions' web URLs in the order they appear in the list (not
    /// the selection set's arbitrary order), so a multi-row Copy reads top to bottom.
    /// Each is resolved against its own account's server URL to honor custom domains.
    private var selectedQuestionURLsInOrder: [String] {
        selectedRowsInOrder.map { $0.item.webURL(baseURL: $0.account.resolvedBaseURL).absoluteString }
    }

    /// The selected rows in list order, carrying their source account, for a
    /// multi-row Copy or Delete.
    var selectedRowsInOrder: [AccountScoped<Question>] {
        sorted.filter { selectedRowIDs.contains($0.id) }
    }

    /// Delete several selected questions at once, each against its own account's
    /// client (per-org), looping the same delete-then-broadcast path the detail view
    /// uses so every list drops the row and the selection follows. Surfaces a failure.
    func bulkDelete(_ rows: [AccountScoped<Question>]) async {
        for row in rows {
            do {
                try await row.account.makeClient().deleteQuestion(id: row.item.id)
                AppRouter.questionDeleted(id: row.item.id, account: row.account.id)
            } catch {
                bulkDeleteError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var questionsOverlay: some View {
        if sorted.isEmpty, !scoped.isEmpty {
            ContentUnavailableView {
                Label("No Matching Questions", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("No questions match the current filters.")
            } actions: {
                Button("Clear Filters") { clearAllFilters() }
            }
        } else if scoped.isEmpty, !isLoading {
            ContentUnavailableView("No Questions", systemImage: "questionmark.bubble")
        }
    }
}
