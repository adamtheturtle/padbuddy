//
//  QuestionsView.swift
//  coderpad
//

// swiftlint:disable file_length

#if os(macOS)
    import AppKit
#endif
import AsyncAlgorithms
import SwiftUI

// swiftlint:disable:next type_body_length
struct QuestionsView: View {
    @State private var clearFiltersPublisherID = UUID()
    @State var discardedFilterNotice: String?
    let client: CoderPadClient
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) var openWindow
    @Environment(\.undoManager) var undoManager
    @Environment(\.windowScope) var windowScope
    #if os(iOS)
        @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    /// While offline the app is read-only, so create/edit/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    @State var accounts = AccountsStore.shared
    @State var nav = AppNavigation.shared
    @State private var cache = QuestionsCacheStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var questions: [Question] = []
    /// Bumped on every mutation of `questions`, so `refreshSorted()` can tell a real
    /// list change from a body pass driven only by the selection (the selection cascade
    /// re-runs `body` several times per click). Mirrors `PadsView.padsRevision` (#395).
    /// Any new assignment to `questions` must bump this.
    @State var questionsRevision = 0
    /// Id index for selection resolution, rebuilt when `questionsRevision` moves on.
    /// Internal, not private: the selection helpers live in QuestionsView+Selection.
    @State var questionIDIndex: (revision: Int, ids: Set<Int>) = (-1, [])

    @State var isLoading = false
    @State var error: (any Error)?
    @State var reloadGeneration = 0
    @Binding var selection: Question?
    /// The list selects by question *id*, not the whole `Question`. `.tag(question)`
    /// makes SwiftUI hash/compare every tag to maintain its selection model, and
    /// `Question`'s synthesized `Hashable` walks every field; an `Int` id tag is a
    /// cheap hash instead. `selection` (the `Question`) stays the detail pane's
    /// source of truth and is kept in sync below. See the same pattern in PadsView.
    @State var selectedQuestionID: Int?
    /// The List's selection. A set so several rows can be selected to copy their
    /// links at once; `selectedQuestionID`/`selection` track the primary within it,
    /// keeping the detail pane and per-account restore/persistence working off one id.
    @State var selectedQuestionIDs: Set<Int> = []
    /// Questions queued for a multi-row delete, awaiting the confirmation dialog, plus
    /// the error from a failed delete. Single-row delete is delegated to the detail
    /// view, but a bulk delete needs its own confirmation + API loop here.
    @State var questionsPendingBulkDelete: [Question]?
    @State var pendingBulkDeleteUndo: PendingBulkDelete<Question>?
    @State var bulkDeleteUndoTask: Task<Void, Never>?
    /// Progress through a committed batch, shown in place of the undo banner once the
    /// grace period is over. Before this a long batch looked like nothing was
    /// happening and could not be stopped partway (#2347).
    @State var bulkDeleteProgress: BulkDeleteProgress?
    @State var bulkDeleteError: String?
    /// Owned by `MainSplit` so the `.searchable` field can live on the split view
    /// (trailing window toolbar) rather than this content column. All the filter,
    /// saved-search, and persistence logic here still reads and writes it.
    @Binding var search: String
    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    @State var draftFilter: String?
    @State var updatedWindow = DateWindow()
    @State var createdWindow = DateWindow()
    @State var dateFilterClockTick = 0
    @State var favoritesOnly = false
    @State var sort: QuestionSort = .lastUsedDesc
    @State var showCreate = false
    /// A favorite picked from the sidebar before the list had loaded it. Held so
    /// the selection can be made once the matching question arrives.
    @State var pendingSelectQuestionID: Int?
    /// Gates the once-per-account restore of persisted live filters so the `onChange`
    /// that saves them doesn't clobber the saved snapshot before restore runs. The
    /// question counterpart to `PadsView.didRestoreFilters`.
    @State var didRestoreFilters = false
    /// Gates the once-per-load restore of the previously-open question, so persistence
    /// doesn't overwrite the saved id before the list has loaded.
    @State var didRestoreSelection = false
    /// The id the list should scroll into view once, set when a previously-open
    /// question is restored on launch. `List(selection:)` doesn't scroll to a
    /// programmatic selection, so without this the restored question stays selected
    /// off-screen with the list pinned to the top. Cleared after the scroll.
    @State var pendingScrollToID: Int?
    /// Debounces free-scroll-position persistence. `FastList` reports each new top
    /// row during scroll; writing every one to `UserDefaults` makes scrolling hitch
    /// on large pad/question lists (#633). Kept as a reference so scroll ticks do not
    /// mutate SwiftUI state just to cancel and replace the pending write.
    @State var topRowPersistence = TopRowPersistenceDebouncer()
    /// Per-render memo of the filtered/sorted rows, favorite ids, and chip options,
    /// refreshed once at the top of `body` so the list's readers share one pass (#365).
    @State var listCache = QuestionsListCache()

    init(client: CoderPadClient, selection: Binding<Question?>, search: Binding<String>) {
        self.client = client
        _selection = selection
        _search = search
        // Seed from the shared cache at construction, so re-entering the Questions
        // section — which rebuilds this view fresh — shows the cached rows on the
        // first frame rather than flashing empty until the `.task` seeds it (#329).
        // In-memory snapshot only, so init stays a pure read with no store mutation
        // mid-update; the `.task` still refreshes (and cold-loads from disk/network).
        if let id = AccountsStore.shared.currentAccountID,
           let warm = QuestionsCacheStore.shared.questionsByAccount[id] {
            _questions = State(initialValue: warm)
        }
    }

    var body: some View {
        // Refresh the per-render memo once, before `sidebar` (and its count subtitle,
        // filter bar, and row list) read `sorted`/`favoriteIDSet`/`available*` (#365).
        refreshSorted()
        return decorated
            .focusedSceneValue(\.questionSortSelection, $sort)
            .focusedSceneValue(\.clearFiltersAction, ClearFiltersAction(
                id: "questions", publisherID: clearFiltersPublisherID,
                perform: clearAllFilters
            ))
    }

    /// `body` is split across these intermediate `some View` properties rather than one
    /// ~16-modifier chain on `sidebar`: a single chain makes the Swift type-checker infer
    /// one deeply-nested generic type that blew the Debug build's 250ms type-check budget
    /// on CI's Xcode 26.5 (warnings-as-errors, ~256ms). Each sub-chain type-checks
    /// independently here, so none exceeds the budget. Order is preserved. (#427)
    private var decorated: some View {
        decoratedObservers
            // Focus-gated so a background window can't consume a request aimed at
            // the focused one (#910); also runs on appear and when focus arrives.
            .consumesWindowRequest(nav.questionsRequest) { applyPendingRequest() }
            // Persist the live filter snapshot whenever any filter changes. Keyed off a
            // stable digest because a fresh `captureCurrentSearch` carries a new UUID
            // each call and would fire endlessly.
            .onChange(of: filterSignature) { _, _ in
                persistFilters()
            }
            .task(id: dateFilterClockActive) { await runDateFilterClock() }
            // Keyed on this account's write generation rather than the cache
            // dictionary, for the same reason as the pads list (#2460).
            .onChange(of: cache.writeGeneration[accounts.currentAccountID ?? UUID()]) { _, _ in
                guard questions.isEmpty, let id = accounts.currentAccountID else { return }

                let warm = cache.cached(id)
                guard !warm.isEmpty else { return }

                questions = warm
                questionsRevision += 1
            }
            // A favorite tapped in the sidebar may arrive before the list has loaded;
            // resolve the deferred selection as soon as the questions land. The
            // last-open question is likewise restored once a list exists for it.
            // `questionsRevision` is bumped wherever `questions` is assigned, so it
            // fires at the same moments — but as an Int compare rather than an O(n)
            // Equatable diff of the whole array on every body pass (#2461).
            .onChange(of: questionsRevision) { _, _ in
                restoreSelectedQuestionIfNeeded()
                resolvePendingSelection()
            }
            .onReloadRequest { await reload(force: true) }
    }

    /// `sidebar` plus the per-session load task and the create/save sheets.
    private var decoratedSheets: some View {
        sidebar
            .task(id: QuestionsTaskKey(apiKey: client.apiKey, baseURL: client.baseURL, phase: scenePhase)) {
                guard scenePhase == .active else { return }

                if questions.isEmpty, let id = accounts.currentAccountID {
                    questions = cache.get(id)
                    questionsRevision += 1
                }
                // Initial load, then refresh on the fixed app cadence.
                await reload()
                var consecutiveFailures = error == nil ? 0 : 1
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
                        consecutiveFailures = error == nil ? 0 : consecutiveFailures + 1
                        break
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                NewQuestionSheet(client: client) { created in
                    questions.insert(created, at: 0)
                    questionsRevision += 1
                    selectedQuestionIDs = [created.id]
                    showCreate = false
                    // Keep the cache in step (as the merged view's insert does), so
                    // New Pad from Question, Spotlight, and a section re-entry see
                    // the new question before the next full reload (#1007).
                    cache.insertQuestion(created, account: accounts.currentAccountID, via: client)
                } onCancel: { showCreate = false }
            }
    }

    // The bulk-delete confirmation, error alert, and update/deletion streams are
    // each applied in their own `some View` getter. As a single chain the getter
    // type-checked in 402ms, over the 250ms budget that warnings-as-errors makes
    // fatal; splitting it stops any one getter from resolving the whole chain.

    /// The bulk-delete confirmation alert.
    private var decoratedConfirm: some View {
        decoratedSheets
            .alert(
                "Delete \(questionsPendingBulkDelete?.count ?? 0) questions?",
                isPresented: .init(get: { questionsPendingBulkDelete != nil },
                                   set: {
                                       if !$0 {
                                           questionsPendingBulkDelete = nil
                                       }
                                   }),
                presenting: questionsPendingBulkDelete
            ) { questions in
                Button("Cancel", role: .cancel) {}
                Button("Delete \(questions.count) Questions", role: .destructive) {
                    scheduleBulkDelete(questions)
                }
            } message: { questions in
                let count = questions.count
                Text("You will have a few seconds to undo before these \(count) questions are permanently deleted.")
            }
    }

    /// The bulk-delete error alert layered on the confirmation dialog.
    private var decoratedAlerts: some View {
        decoratedConfirm
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

    /// The live question-update stream layered on the alerts.
    private var decoratedUpdateStream: some View {
        decoratedAlerts
            .task {
                for await update in AppRouter.questionUpdates {
                    // Per-org ids collide across accounts, so ignore a mutation the
                    // poster scoped to a different account than this view shows.
                    guard scopedToThisAccount(update.account) else { continue }

                    let question = update.question
                    if let index = questions.firstIndex(where: { $0.id == question.id }) {
                        questions[index] = question
                        questionsRevision += 1
                        if selection?.id == question.id {
                            selection = question
                        }
                        // Write the edit through to the cache (deletions already do),
                        // so a section re-entry and Spotlight don't serve the stale
                        // pre-edit row until the next full reload (#1005).
                        cache.updateQuestion(question, account: accounts.currentAccountID, via: client)
                    }
                }
            }
    }

    /// The live question-deletion stream layered on the update stream.
    private var decoratedStreams: some View {
        decoratedUpdateStream
            .task {
                for await deletion in AppRouter.questionDeletions {
                    guard scopedToThisAccount(deletion.account) else { continue }

                    let id = deletion.id
                    // Drop the deleted id from the selection. If it was the primary,
                    // move to a neighbor (computed while `questions` still holds the
                    // row) only when no other rows stay selected; otherwise the primary
                    // falls to a still-selected row via the `selectedQuestionIDs` observer.
                    let wasPrimary = selection?.id == id
                    let neighbor = wasPrimary ? neighborSelection(forDeletedQuestion: id) : nil
                    selectedQuestionIDs.remove(id)
                    questions.removeAll { $0.id == id }
                    questionsRevision += 1
                    if wasPrimary, selectedQuestionIDs.isEmpty {
                        selectedQuestionIDs = neighbor.map { [$0.id] } ?? []
                    }
                }
            }
    }

    /// The appear-time restore and the early selection/account observers.
    private var decoratedObservers: some View {
        decoratedStreams
            .onAppear {
                // Restore first so a deep-link/favorite request can still override
                // it (the request is consumed by the focus-gated observer, which
                // also runs on appear).
                restoreFilters()
                selectedQuestionIDs = selection.map { [$0.id] } ?? []
            }
            // The List edits `selectedQuestionIDs`; derive the primary row from it so
            // the detail pane, restore, and persistence keep working off the single
            // `selectedQuestionID`. One-way (set → primary), so there's no binding loop.
            .onChange(of: selectedQuestionIDs) { previous, current in
                let primary = MultiSelectLogic.primaryID(previous: previous, current: current)
                if selectedQuestionID != primary {
                    selectedQuestionID = primary
                }
                // Resolve the detail-pane `Question` in the same pass rather than via a
                // second `onChange(selectedQuestionID)`. A click re-runs `body` once per
                // state write, and each pass rebuilds the list's prepared rows — so
                // collapsing selectedQuestionIDs → selectedQuestionID → selection into one
                // update removes a full list rebuild per click on a large list (mirrors the
                // PadsView fix). `selectedQuestionID` is only ever derived here or from an
                // external `selection` change (below), so no separate writer needs a bridge.
                if selection?.id != primary {
                    selection = primary.flatMap { id in questions.first { $0.id == id } }
                }
                // Remember the open question per account so it reopens next launch. Deferred
                // off the click's synchronous path: it writes UserDefaults, and a UserDefaults
                // change re-reads the @AppStorage-backed sort mid-update, which re-invalidated
                // the whole list (an extra full rebuild) on every click.
                // The id and account are captured now so the deferred write can't land
                // under a different account after a fast switch (#757).
                let persistID = selectedQuestionID
                let persistAccount = accounts.currentAccountID
                Task { @MainActor in persistSelectedQuestion(persistID, account: persistAccount) }
            }
            .onChange(of: selection) { _, newValue in
                if selectedQuestionID != newValue?.id {
                    selectedQuestionID = newValue?.id
                }
            }
            // The account id is often nil on first appear; restore once it lands, and
            // swap to the new account's saved filters whenever the account changes.
            .onChange(of: accounts.currentAccountID) { _, _ in restoreFiltersForAccountChange() }
    }

    /// Applies any request queued by `AppNavigation`, then clears it. See the
    /// matching method in `PadsView` for the appear-vs-change rationale.
    private func applyPendingRequest() {
        guard let request = nav.questionsRequest else { return }

        nav.questionsRequest = nil
        guard request.accountScope?.isCurrent == true else { return }

        if let saved = request.applySearch {
            apply(saved)
        }
        if let query = request.search {
            search = query
        }
        // Offline the app is read-only: opening the create sheet would offer a
        // submit that can only fail, so drop the request like the merged view (#1002).
        if request.startCreating, !isReadOnly {
            showCreate = true
        }
        if let id = request.selectQuestionID,
           request.selectQuestionAccountID == nil || request.selectQuestionAccountID == accounts.currentAccountID,
           request.selectQuestionClientIdentity == nil
           || request.selectQuestionClientIdentity == accounts.currentAccount?.makeClient().taskIdentity {
            selectQuestion(id: id)
        }
    }

    /// Selects the question with `id`, deferring until the list loads it when the
    /// favorite was picked before the questions arrived (e.g. right after a cold
    /// launch). `resolvePendingSelection` completes the deferred case.
    func reload(force _: Bool = false) async {
        guard !client.apiKey.isEmpty else { return }

        reloadGeneration &+= 1
        let generation = reloadGeneration
        let owningID = accounts.account(matching: client)?.id ?? accounts.currentAccountID
        guard let owningID, let cacheLoad = cache.beginLoad(owningID, via: client) else { return }

        isLoading = true
        error = nil
        defer {
            if generation == reloadGeneration {
                isLoading = false
            }
        }
        do {
            // Foreground lists must paint page 1 immediately. Waiting for the shared
            // complete-list read leaves large organizations blank until every page
            // arrives; an account with tens of thousands of records can take minutes.
            let isInitialLoad = questions.isEmpty
            var fetched: [Question] = []
            for try await snapshot in client.listQuestionsIncrementally() {
                guard generation == reloadGeneration, !Task.isCancelled else { return }

                if isLoading {
                    isLoading = false
                }
                fetched = snapshot
                if isInitialLoad {
                    questions = snapshot
                    questionsRevision += 1
                    cache.set(owningID, questions: snapshot, via: client,
                              persist: false, accepting: cacheLoad)
                }
            }
            guard generation == reloadGeneration, !Task.isCancelled else { return }

            questions = fetched
            questionsRevision += 1
            cache.set(owningID, questions: fetched, via: client, accepting: cacheLoad)
            // Every page has arrived, so a saved selection that still isn't here is
            // genuinely gone. Idempotent — a restore already made from a complete
            // enough list is a no-op (#2501).
            restoreSelectedQuestionIfNeeded(loadComplete: true)
        } catch {
            guard generation == reloadGeneration else { return }

            // Keep whatever is already on screen; the error view only takes over when
            // there's nothing loaded (gated on `questions.isEmpty`).
            self.error = error
        }
    }
}
