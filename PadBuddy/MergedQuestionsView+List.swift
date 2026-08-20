// swiftlint:disable file_length
//
//  MergedQuestionsView+List.swift
//  coderpad
//
//  list. Kept out of the primary struct so its body-length stays small.
//

#if os(macOS)
    import AppKit
#endif
import AsyncAlgorithms
import FastList
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
            .task(id: MergedQuestionsTaskKey(accountKey: accountKey, phase: scenePhase)) {
                guard scenePhase == .active else { return }

                seedFromCache()
                // Reopen the question selected last session, once the seeded cache (or
                // the reload below) provides a list to resolve it against.
                restoreSelectedRowIfNeeded()
                // Initial load, then refresh on the fixed app cadence.
                await reload()
                var consecutiveFailures = accountErrors.isEmpty ? 0 : 1
                while !Task.isCancelled {
                    let interval = max(
                        AutoRefreshPolicy.interval(
                            base: GeneralSettings.refreshInterval,
                            consecutiveFailures: consecutiveFailures
                        ),
                        .milliseconds(1)
                    )
                    for await _ in AsyncTimerSequence.repeating(every: interval) {
                        await reload()
                        consecutiveFailures = accountErrors.isEmpty ? 0 : consecutiveFailures + 1
                        break
                    }
                }
            }
            .onAppear {
                // Restore the filters the list was left with last session; a queued
                // New Question or wholesale-search request is consumed by the
                // focus-gated observer (which also runs on appear), so it can still
                // override the restored state (#1000).
                restoreFilters()
                // Prefer the row in the account the selection was made in (tracked
                // by the router): per-org question ids collide, so the bare id can
                // otherwise re-select a different account's same-id row (#710).
                let restored = selection.flatMap { sel in
                    scoped.first { $0.item.id == sel.id && $0.account.id == router.selectedQuestionAccountID }
                        ?? scoped.first { $0.item.id == sel.id }
                }
                selectedRowIDs = restored.map { [$0.id] } ?? []
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
                if selectedRowID != primary {
                    selectedRowID = primary
                }
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
            // simply won't resolve, the same best-effort the per-account view uses).
            // simply will not resolve, the same best-effort the per-account view uses).
            // Focus-gated and attempted on appear: the tap can also switch the
            // section, so the pending favourite is set before this list mounts and
            // a change-only observer would drop it (#1016). Scroll the row into
            // view too - the selection alone can land off-screen in a long list (#1019).
            .consumesWindowRequest(nav.pendingMergedFavoriteQuestion) {
                guard let request = nav.pendingMergedFavoriteQuestion else { return }

                nav.pendingMergedFavoriteQuestion = nil
                if let requestedIdentity = request.clientIdentity {
                    let currentIdentity = accounts.mergeableAccounts
                        .first(where: { $0.id == request.account })?.makeClient().taskIdentity
                    guard requestedIdentity == currentIdentity else { return }
                }
                let rowID = Self.rowID(account: request.account, question: request.id)
                selectedRowIDs = [rowID]
                pendingScrollToRowID = rowID
            }
            // Keep the sidebar's "My Questions" row in sync with this list's "Mine"
            // preset: publish the live state and consume any sidebar toggle, the
            // same bridge `MergedPadsView` uses for "My Pads". Consumption is
            // focus-gated so a background window can't steal the toggle (#910).
            .onChange(of: mineOnly, initial: true) { _, isOn in publishMergedQuestionsMineOnly(isOn) }
            .consumesWindowRequest(nav.mergedQuestionsMineRequest) {
                consumeMergedQuestionsMineRequest(nav.mergedQuestionsMineRequest)
            }
            // Consume navigation requests routed to Questions (New Question, a
            // wholesale search) so they work in merged mode too, keeping the
            // semantics aligned with `QuestionsView` and `MergedPadsView` (#1000).
            .consumesWindowRequest(nav.questionsRequest) { applyPendingRequest() }
    }

    private func publishMergedQuestionsMineOnly(_ isOn: Bool) {
        let windowNav = windowNav
        guard windowNav.mergedQuestionsMineOnly != isOn else { return }

        DispatchQueue.main.async {
            if windowNav.mergedQuestionsMineOnly != isOn {
                windowNav.mergedQuestionsMineOnly = isOn
            }
        }
    }

    private func consumeMergedQuestionsMineRequest(_ request: Bool?) {
        guard let request else { return }

        DispatchQueue.main.async {
            guard nav.mergedQuestionsMineRequest != nil else { return }

            nav.mergedQuestionsMineRequest = nil
            if mineOnly != request {
                mineOnly = request
            }
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
                    guard let account = deletion.account else { continue }

                    // Drop every selected row matching the deleted question (matched by
                    // account too, since per-org ids collide). If the primary was among
                    // them, move to a neighbor — computed while `sorted` still holds the
                    // row — but only when no other rows remain selected.
                    let removed = selectedRowIDs.filter { rowID in
                        guard let row = row(forRowID: rowID) else { return false }

                        return row.item.id == id && row.account.id == account
                    }
                    let primaryDeleted = selectedRowID.map { removed.contains($0) } ?? false
                    let neighbor = primaryDeleted
                        ? selectedRowID.flatMap { neighborRowID(forDeletedRowID: $0) } : nil
                    selectedRowIDs.subtract(removed)
                    removeQuestion(id: id, account: account)
                    if primaryDeleted, selectedRowIDs.isEmpty {
                        selectedRowIDs = neighbor.map { [$0] } ?? []
                    }
                }
            }
            .onReloadRequest { await reload(force: true) }
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
                                   set: {
                                       if !$0 {
                                           rowsPendingBulkDelete = nil
                                       }
                                   }),
                presenting: rowsPendingBulkDelete
            ) { rows in
                Button("Cancel", role: .cancel) {}
                Button("Delete \(rows.count) Questions", role: .destructive) {
                    scheduleBulkDelete(rows)
                }
            } message: { rows in
                Text("You will have a few seconds to undo before these \(rows.count) questions "
                    + "are permanently deleted.")
            }
            .alert("Could not delete question",
                   isPresented: .init(get: { bulkDeleteError != nil },
                                      set: {
                                          if !$0 {
                                              bulkDeleteError = nil
                                          }
                                      })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bulkDeleteError ?? "")
            }
            .overlay(alignment: .bottom) { bulkDeleteUndoBanner }
            // A pending bulk delete must die with the list: once the view (and its
            // Undo banner) is gone, letting the grace-period task fire would delete
            // with no remaining way to undo (#1018, mirroring #870).
            .onDisappear { cancelBulkDelete() }
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
                            nav.deleteQuestionID = .init(id: row.item.id, account: row.account.id)
                        }]
                },
                pasteboardItem: { questionPasteboardItem($0) },
                menuItems: { questionTableMenuItems($0) },
                onTopRowChange: { scheduleTopRowPersistence($0) },
                onDragSessionBegan: FavoriteDragLifecycle.onBegan(in: windowScope),
                onDragSessionEnded: FavoriteDragLifecycle.onEnded(in: windowScope)
            )
            .overlay { questionsOverlay }
            .macPullToRefresh { await reload(force: true) }
            .focusedSceneValue(\.focusedQuestion, selection)
            .focusedSceneValue(\.focusedQuestionAccountID, router.selectedQuestionAccountID)
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
                .accessibilityIdentifier("question-row-\(row.account.id.uuidString)-\(row.item.id)")
                .fastListRowManualSelection(id: row.id, selection: $selectedRowIDs)
                .favoriteDraggable(questionFavoritePayload(row), title: row.item.displayTitle)
                .favoriteRowContextMenu(questionTableMenuItems(row), title: row.item.displayTitle)
            }
            .rowContentID(mergedQuestionListReloadID)
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
                        nav.deleteQuestionID = .init(id: row.item.id, account: row.account.id)
                    }]
            }
            .onTopRowChange { scheduleTopRowPersistence($0) }
            .scrollToRow(id: pendingScrollToRowID) { pendingScrollToRowID = nil }
            .overlay { questionsOverlay }
            .macPullToRefresh { await reload(force: true) }
            .focusedSceneValue(\.focusedQuestion, selection)
            .focusedSceneValue(\.focusedQuestionAccountID, router.selectedQuestionAccountID)
        #endif
    }

    /// Read on every body pass — the selection cascade re-runs `body` several times per
    /// click — so it stays an interpolation of three Ints. Rebuilding a favourite id
    /// string per mergeable account cost O(total favorites) allocations per render
    /// (#2082). The scoped signature stands in for the mergeable account set, which
    /// decides whose favourites apply.
    private var mergedQuestionListReloadID: String {
        // Fold the content revision in so an in-place edit (rename, language, type)
        // redraws the visible row: the id list alone can't see it (#1003).
        "\(favorites.revision)#\(questionsRevision)#\(scopedCache.signature ?? 0)"
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
    /// uses so every list drops the row and the selection follows. Failures are
    /// aggregated into one report naming the questions that remain, rather than each
    /// failure overwriting the previous one (#1208).
    func bulkDelete(_ rows: [MergedQuestionRow]) async {
        let live = accounts
        let outcome = await BulkDeleteRunner.run(
            rows,
            title: \.item.displayTitle,
            onProgress: { bulkDeleteProgress = $0 },
            delete: { row in
                // The undo grace period can outlive an account change: a row whose
                // account was removed or re-keyed meanwhile must not fire a
                // destructive delete through credentials the user just revoked or
                // replaced (#1259).
                guard let current = live.accounts.first(where: { $0.id == row.account.id }),
                      !current.pointsAtDifferentBackend(than: row.account) else {
                    return BulkDeleteUndo.CredentialsChangedError.accountRemovedOrRekeyed
                }

                do {
                    let client = current.makeClient()
                    try await client.deleteQuestion(id: row.item.id)
                    AppRouter.questionDeleted(id: row.item.id, account: row.account.id, via: client)
                    return nil
                } catch {
                    return error
                }
            }
        )
        bulkDeleteProgress = nil
        bulkDeleteError = BulkDeleteUndo.report(outcome, total: rows.count, kind: .questions)
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
