//
//  MergedQuestionsView+List.swift
//  coderpad
//
//  The view body, list, rows, and lifecycle modifiers for the combined questions
//  list. Kept out of the primary struct so its body-length stays small.
//

#if os(macOS)
    import AppKit
#endif
import AsyncAlgorithms
import MacPullToRefresh
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
            .task(id: QuestionsTaskKey(apiKey: accountKey, baseURL: nil, phase: scenePhase)) {
                guard scenePhase == .active else { return }

                seedFromCache()
                // Reopen the question selected last session, once the seeded cache (or
                // the reload below) provides a list to resolve it against.
                restoreSelectedRowIfNeeded()
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
                // Restore the filters the list was left with last session before
                // bridging the selection, so the list opens in the same view.
                restoreFilters()
                selectedRowIDs = selection
                    .flatMap { sel in scoped.first { $0.item.id == sel.id }?.id }
                    .map { [$0] } ?? []
            }
            .onChange(of: cache.questionsByAccount) { _, _ in hydrateFromCacheIfEmpty() }
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
            .onChange(of: mineOnly, initial: true) { _, isOn in publishMergedQuestionsMineOnly(isOn) }
            .onChange(of: nav.mergedQuestionsMineRequest, initial: true) { _, request in
                consumeMergedQuestionsMineRequest(request)
            }
    }

    private func publishMergedQuestionsMineOnly(_ isOn: Bool) {
        guard nav.mergedQuestionsMineOnly != isOn else { return }

        DispatchQueue.main.async {
            if nav.mergedQuestionsMineOnly != isOn { nav.mergedQuestionsMineOnly = isOn }
        }
    }

    private func consumeMergedQuestionsMineRequest(_ request: Bool?) {
        guard let request else { return }

        DispatchQueue.main.async {
            guard nav.mergedQuestionsMineRequest != nil else { return }

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
                    let row = MergedQuestionRow(account: account, item: created)
                    select(row)
                    selectedRowIDs = [row.id]
                    creatingForAccount = nil
                } onCancel: {
                    creatingForAccount = nil
                }
            }
            .alert(
                "Delete \(rowsPendingBulkDelete?.count ?? 0) questions?",
                isPresented: .init(get: { rowsPendingBulkDelete != nil },
                                   set: { if !$0 { rowsPendingBulkDelete = nil } }),
                presenting: rowsPendingBulkDelete
            ) { rows in
                Button("Cancel", role: .cancel) {}
                Button("Delete \(rows.count) Questions", role: .destructive) {
                    scheduleBulkDelete(rows)
                }
            } message: { rows in
                Text("You'll have a few seconds to undo before these \(rows.count) questions are permanently deleted.")
            }
            .alert("Couldn't delete question",
                   isPresented: .init(get: { bulkDeleteError != nil },
                                      set: { if !$0 { bulkDeleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bulkDeleteError ?? "")
            }
            .overlay(alignment: .bottom) { bulkDeleteUndoBanner }
    }

    var content: some View {
        VStack(spacing: 0) {
            filterBar
            errorBar
            Divider()
            questionsList
        }
        .transition(.opacity)
        .id("content")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isLoading && !scoped.isEmpty)
        // Surface the count beneath the "Questions" title in the window toolbar
        // rather than as an inline bar above the list.
        .reportsSectionCount(countSubtitle)
        .toolbar(id: "merged-questions") { questionsToolbar }
    }

    private var questionsList: some View {
        #if os(macOS)
            MacQuestionTable(
                items: sorted,
                selection: $selectedRowIDs,
                reloadID: mergedQuestionListReloadID,
                scrollToID: pendingScrollToRowID,
                onScrolledToID: { pendingScrollToRowID = nil },
                presentation: { $0.presentation },
                rowAccount: { $0.rowAccount },
                isFavorite: { isFavorite($0) },
                toggleFavorite: { toggleFavorite($0) },
                onDoubleClick: { openQuestionWindow($0) },
                onReturn: { openQuestionWindow($0) },
                leadingActions: { row in
                    let starred = isFavorite(row)
                    return [SwipeAction(
                        title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                        tint: Color(platformColor: .systemYellow),
                        systemImage: starred ? "star.slash" : "star.fill"
                    ) { toggleFavorite(row) }]
                },
                trailingActions: { row in
                    guard !isReadOnly else { return [] }

                    return [SwipeAction(title: String(localized: "Delete"), role: .destructive,
                                        systemImage: "trash") {
                            select(row)
                            nav.deleteQuestionID = row.item.id
                        }]
                },
                pasteboardItem: { questionPasteboardItem($0) },
                menuItems: { questionTableMenuItems($0) },
                onTopRowChange: { scheduleTopRowPersistence($0) }
            )
            .overlay { questionsOverlay }
            .macPullToRefresh { await reload() }
            .focusedSceneValue(\.focusedQuestion, selection)
            .onCopyCommand(perform: copyLinkCommand(hasSelection: !selectedRowIDs.isEmpty) {
                selectedQuestionURLsInOrder.joined(separator: "\n")
            })
        #else
            FastList(sorted, selection: $selectedRowIDs) { row in
                QuestionRowHostableContent(
                    question: row.item,
                    presentation: row.presentation,
                    rowAccount: row.rowAccount,
                    isFavorite: isFavorite(row),
                    onToggleFavorite: { toggleFavorite(row) }
                )
                .fastListRowManualSelection(id: row.id, selection: $selectedRowIDs)
                .favoriteDraggable(questionFavoritePayload(row), title: row.item.displayTitle)
                .favoriteRowContextMenu(questionTableMenuItems(row), title: row.item.displayTitle)
            }
            .reloadID(mergedQuestionListReloadID)
            .onDoubleClick { openQuestionWindow($0) }
            .onReturnKey { openQuestionWindow($0) }
            .swipeActions(edge: .leading) { row in
                let starred = isFavorite(row)
                return [SwipeAction(
                    title: starred ? String(localized: "Unfavorite") : String(localized: "Favorite"),
                    tint: Color(platformColor: .systemYellow),
                    systemImage: starred ? "star.slash" : "star.fill"
                ) { toggleFavorite(row) }]
            }
            .swipeActions(edge: .trailing) { row in
                guard !isReadOnly else { return [] }

                return [SwipeAction(title: String(localized: "Delete"), role: .destructive,
                                    systemImage: "trash") {
                        select(row)
                        nav.deleteQuestionID = row.item.id
                    }]
            }
            .onTopRowChange { scheduleTopRowPersistence($0) }
            .scrollToRow(id: pendingScrollToRowID) { pendingScrollToRowID = nil }
            .overlay { questionsOverlay }
            .macPullToRefresh { await reload() }
            .focusedSceneValue(\.focusedQuestion, selection)
        #endif
    }

    private var mergedQuestionListReloadID: String {
        accounts.mergeableAccounts
            .map { account in
                let ids = favorites.favorites(account: account.id).map(String.init).joined(separator: ",")
                return "\(account.id.uuidString):\(ids)"
            }
            .joined(separator: "|")
    }

    /// Opens a combined-list question in its own window with its originating account.
    private func openQuestionWindow(_ row: MergedQuestionRow) {
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
    var selectedRowsInOrder: [MergedQuestionRow] {
        sorted.filter { selectedRowIDs.contains($0.id) }
    }

    /// Delete several selected questions at once, each against its own account's
    /// client (per-org), looping the same delete-then-broadcast path the detail view
    /// uses so every list drops the row and the selection follows. Surfaces a failure.
    func bulkDelete(_ rows: [MergedQuestionRow]) async {
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
            } actions: {
                Button("Clear Filters") { clearAllFilters() }
            }
        } else if scoped.isEmpty, !isLoading {
            // Spell out that this account set is genuinely empty, so it doesn't read as
            // still-loading or over-filtered (#618).
            ContentUnavailableView {
                Label("No Questions", systemImage: "questionmark.bubble")
            } description: {
                Text("Questions from your accounts' banks will appear here.")
            }
        }
    }
}
