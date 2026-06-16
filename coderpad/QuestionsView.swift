//
//  QuestionsView.swift
//  coderpad
//

import AppKit
import SwiftUI

struct QuestionsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) var openWindow
    /// While offline the app is read-only, so create/edit/delete controls disable (#321).
    @Environment(\.isReadOnly) var isReadOnly
    /// Long-lived target for the list's native double-click-to-open (see
    /// `TableDoubleClickProxy`); opens the selected question in its own window.
    @State var doubleClickProxy = TableDoubleClickProxy()
    @State var accounts = AccountsStore.shared
    @State var nav = AppNavigation.shared
    @State private var cache = QuestionsCacheStore.shared
    @State var favorites = FavoriteQuestionsStore.shared
    @State var questions: [Question] = []

    @State var isLoading = false
    @State var error: Error?
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
    @State var bulkDeleteError: String?
    /// Owned by `MainSplit` so the `.searchable` field can live on the split view
    /// (trailing window toolbar) rather than this content column. All the filter,
    /// saved-search, and persistence logic here still reads and writes it.
    @Binding var search: String
    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    @State var draftFilter: String?
    @State var favoritesOnly = false
    @AppStorage(QuestionSort.storageKey) var sort: QuestionSort = .lastUsedDesc
    @State var showCreate = false
    @State var savedSearches = SavedSearchStore.shared
    @State var showSaveSearch = false
    @State var saveSearchName = ""
    @State var isSuggestingName = false
    /// Natural-language filter entry: the sheet's visibility, the typed query, and
    /// whether the on-device interpreter is running. See `SearchInterpreter`.
    @State var showSmartFilter = false
    @State var smartFilterText = ""
    @State var isInterpreting = false
    @State var smartFilterFailed = false
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
        sidebar
            .task(id: QuestionsTaskKey(apiKey: client.apiKey, phase: scenePhase)) {
                guard scenePhase == .active else { return }
                if questions.isEmpty, let id = accounts.currentAccountID {
                    questions = cache.get(id)
                }
                // Closure form so a change to the interval in Settings takes effect on
                // the next cycle without restarting the task.
                await periodicReload(interval: { GeneralSettings.refreshInterval }, work: {
                    await reload()
                })
            }
            .sheet(isPresented: $showCreate) {
                NewQuestionSheet(client: client) { created in
                    questions.insert(created, at: 0)
                    selectedQuestionIDs = [created.id]
                    showCreate = false
                } onCancel: { showCreate = false }
            }
            .sheet(isPresented: $showSaveSearch) {
                SaveSearchSheet(
                    name: $saveSearchName,
                    prompt: Text("e.g. My drafts, Python"),
                    showsSuggest: SavedSearchNamer.isAvailable,
                    isSuggesting: isSuggestingName,
                    onSuggest: suggestName,
                    onCommit: commitSavedSearch,
                    onCancel: { showSaveSearch = false }
                )
            }
            .sheet(isPresented: $showSmartFilter) {
                SmartFilterSheet(
                    text: $smartFilterText,
                    isInterpreting: isInterpreting,
                    failed: smartFilterFailed,
                    placeholder: "e.g. my draft SQL questions",
                    onSubmit: { Task { await applySmartFilter() } },
                    onCancel: { showSmartFilter = false }
                )
            }
            .confirmationDialog(
                "Delete \(questionsPendingBulkDelete?.count ?? 0) questions?",
                isPresented: .init(get: { questionsPendingBulkDelete != nil },
                                   set: { if !$0 { questionsPendingBulkDelete = nil } }),
                titleVisibility: .visible,
                presenting: questionsPendingBulkDelete
            ) { questions in
                Button("Delete \(questions.count) Questions", role: .destructive) {
                    Task { await bulkDelete(questions) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { questions in
                Text("These \(questions.count) questions will be permanently deleted. This can't be undone.")
            }
            .alert("Couldn't delete question",
                   isPresented: .init(get: { bulkDeleteError != nil },
                                      set: { if !$0 { bulkDeleteError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(bulkDeleteError ?? "")
            }
            .task {
                for await update in AppRouter.questionUpdates {
                    // Per-org ids collide across accounts, so ignore a mutation the
                    // poster scoped to a different account than this view shows.
                    guard scopedToThisAccount(update.account) else { continue }
                    let question = update.question
                    if let index = questions.firstIndex(where: { $0.id == question.id }) {
                        questions[index] = question
                        if selection?.id == question.id { selection = question }
                    }
                }
            }
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
                    // Keep the disk cache and Spotlight index in step; otherwise the
                    // deleted question lingers there until a full reload.
                    cache.removeQuestion(id: id, account: accounts.currentAccountID)
                    if wasPrimary, selectedQuestionIDs.isEmpty {
                        selectedQuestionIDs = neighbor.map { [$0.id] } ?? []
                    }
                }
            }
            .onAppear {
                // Restore first so a deep-link/favorite request can still override it.
                restoreFilters()
                applyPendingRequest()
                publishLiveFilter()
                selectedQuestionIDs = selection.map { [$0.id] } ?? []
                // Double-clicking a row opens the selected question in its own window
                // (the first click selects it). Reads `selection` live.
                doubleClickProxy.onDoubleClick = {
                    guard let question = selection else { return }
                    openWindow(id: "question",
                               value: QuestionWindowID(account: accounts.currentAccountID, id: question.id))
                }
            }
            // The List edits `selectedQuestionIDs`; derive the primary row from it so
            // the detail pane, restore, and persistence keep working off the single
            // `selectedQuestionID`. One-way (set → primary), so there's no binding loop.
            .onChange(of: selectedQuestionIDs) { previous, current in
                let primary = MultiSelectLogic.primaryID(previous: previous, current: current)
                if selectedQuestionID != primary { selectedQuestionID = primary }
            }
            // Bridge the lightweight list selection (`selectedQuestionID`) to the
            // `Question` binding the detail pane reads. Each side writes only when the
            // id truly differs, so the two `onChange`s can't ping-pong.
            .onChange(of: selectedQuestionID) { _, newID in
                if selection?.id != newID {
                    selection = newID.flatMap { id in questions.first { $0.id == id } }
                }
                // Remember the open question per account so it reopens next launch.
                persistSelectedQuestion()
            }
            .onChange(of: selection) { _, newValue in
                if selectedQuestionID != newValue?.id { selectedQuestionID = newValue?.id }
            }
            // The account id is often nil on first appear; restore once it lands, and
            // swap to the new account's saved filters whenever the account changes.
            .onChange(of: accounts.currentAccountID) { _, _ in restoreFiltersForAccountChange() }
            .onChange(of: nav.questionsRequest) { _, _ in applyPendingRequest() }
            // Republish the live filter so the sidebar highlights whichever suggested or
            // saved row is applied, and falls back to the plain "Questions" row the moment
            // any filter is edited. Keyed off a stable digest because a fresh
            // `captureCurrentSearch` carries a new UUID each call and would fire endlessly.
            .onChange(of: filterSignature) { _, _ in
                persistFilters()
                publishLiveFilter()
            }
            // A favorite tapped in the sidebar may arrive before the list has loaded;
            // resolve the deferred selection as soon as the questions land. The
            // last-open question is likewise restored once a list exists for it.
            .onChange(of: questions) { _, _ in
                restoreSelectedQuestionIfNeeded()
                resolvePendingSelection()
            }
            .task {
                for await _ in AppRouter.reloads {
                    await reload()
                }
            }
    }

    /// Applies any request queued by `AppNavigation`, then clears it. See the
    /// matching method in `PadsView` for the appear-vs-change rationale.
    private func applyPendingRequest() {
        guard let request = nav.questionsRequest else { return }
        nav.questionsRequest = nil
        if let saved = request.applySearch { apply(saved) }
        if let query = request.search { search = query }
        if request.startCreating { showCreate = true }
        if let id = request.selectQuestionID { selectQuestion(id: id) }
    }

    /// Selects the question with `id`, deferring until the list loads it when the
    /// favorite was picked before the questions arrived (e.g. right after a cold
    /// launch). `resolvePendingSelection` completes the deferred case.
    private func selectQuestion(id: Int) {
        if let match = questions.first(where: { $0.id == id }) {
            selectedQuestionIDs = [match.id]
            // Reveal it: a favorite picked from the sidebar may sit far down the list.
            pendingScrollToID = match.id
            pendingSelectQuestionID = nil
        } else {
            pendingSelectQuestionID = id
        }
    }

    private func resolvePendingSelection() {
        guard let id = pendingSelectQuestionID,
              let match = questions.first(where: { $0.id == id }) else { return }
        selectedQuestionIDs = [match.id]
        pendingScrollToID = match.id
        pendingSelectQuestionID = nil
    }

    func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // On the first load, render page 1 immediately and grow the list as later
            // pages stream in. On a refresh we already have content, so only swap in the
            // complete result at the end — otherwise a later page failing would
            // transiently shrink the visible list to just page 1.
            let isInitialLoad = questions.isEmpty
            var fetched: [Question] = []
            for try await snapshot in client.listQuestionsIncrementally() {
                fetched = snapshot
                if isInitialLoad { questions = snapshot }
            }
            questions = fetched
            if let id = accounts.currentAccountID {
                cache.set(id, questions: fetched)
            }
        } catch {
            // Keep whatever is already on screen; the error view only takes over when
            // there's nothing loaded (gated on `questions.isEmpty`).
            self.error = error
        }
    }
}

struct QuestionsTaskKey: Hashable {
    let apiKey: String
    let phase: ScenePhase
}
