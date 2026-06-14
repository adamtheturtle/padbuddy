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
    @State private var pendingSelectQuestionID: Int?
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
                saveSearchSheet
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

    private var saveSearchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Search").font(.title3.bold())
            HStack(spacing: 8) {
                TextField("Name", text: $saveSearchName, prompt: Text("e.g. My drafts, Python"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitSavedSearch() }
                    .onChange(of: saveSearchName) { _, newValue in
                        if newValue.count > NamedSearch.maxNameLength {
                            saveSearchName = String(newValue.prefix(NamedSearch.maxNameLength))
                        }
                    }
                if SavedSearchNamer.isAvailable {
                    suggestNameButton
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showSaveSearch = false }
                Button("Save") { commitSavedSearch() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 360)
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

    static func selectedQuestionKey(_ account: UUID) -> String {
        "questions.selectedQuestion.\(account.uuidString)"
    }

    /// Persist the id of the question shown in the detail pane, per account, so the
    /// list reopens to it next launch. Skipped until the restore has run so the empty
    /// startup state can't clobber the saved id; clearing the selection removes the
    /// stored id so a blank detail pane is restored faithfully too.
    func persistSelectedQuestion() {
        guard didRestoreSelection, let account = accounts.currentAccountID else { return }
        let key = Self.selectedQuestionKey(account)
        if let selectedQuestionID {
            UserDefaults.standard.set(selectedQuestionID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The saved question to reselect on launch: the stored id, but only when nothing
    /// is already selected, no navigation is pending, and the id is still in the loaded
    /// list. Pure so the restore decision is unit-testable in isolation.
    static func questionToRestore(
        savedID: Int?,
        hasSelection: Bool,
        hasPendingNavigation: Bool,
        availableIDs: Set<Int>
    ) -> Int? {
        guard !hasSelection, !hasPendingNavigation,
              let savedID, availableIDs.contains(savedID) else { return nil }
        return savedID
    }

    /// Restore the previously-open question once its list is loaded. Marks the restore
    /// complete as soon as questions exist (so later changes persist), then reselects
    /// via `questionToRestore` — which yields to a pending favorite or queued request
    /// so an explicit navigation always wins.
    func restoreSelectedQuestionIfNeeded() {
        guard !didRestoreSelection, !questions.isEmpty else { return }
        didRestoreSelection = true
        guard let account = accounts.currentAccountID else { return }
        let stored = UserDefaults.standard.object(forKey: Self.selectedQuestionKey(account)) as? Int
        guard let id = Self.questionToRestore(
            savedID: stored,
            hasSelection: selection != nil,
            hasPendingNavigation: pendingSelectQuestionID != nil || nav.questionsRequest != nil,
            availableIDs: Set(questions.map(\.id))
        ) else { return }
        selectedQuestionIDs = [id]
        // Bring the restored row into view; the List won't scroll to it on its own.
        pendingScrollToID = id
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

/// Sort orders offered for the Questions list. "Last used" is backed by the
/// question's `updatedAt` timestamp — the API exposes no distinct last-used date.
enum QuestionSort: String, CaseIterable, Identifiable {
    case lastUsedDesc
    case lastUsedAsc
    case usedDesc
    case usedAsc
    case titleAsc
    case titleDesc

    /// `@AppStorage` key shared by both Questions lists and the Question menu's
    /// "Sort By" command, so changing the sort anywhere keeps them all in sync.
    static let storageKey = "questions.sort"

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .lastUsedDesc: "Last used (newest first)"
        case .lastUsedAsc: "Last used (oldest first)"
        case .usedDesc: "Most used"
        case .usedAsc: "Least used"
        case .titleAsc: "Title (A-Z)"
        case .titleDesc: "Title (Z-A)"
        }
    }

    /// The field this sort orders by, independent of direction.
    var field: QuestionSortField {
        switch self {
        case .lastUsedDesc, .lastUsedAsc: .lastUsed
        case .usedDesc, .usedAsc: .used
        case .titleAsc, .titleDesc: .title
        }
    }

    /// The two directions available for `field`, in menu order, each with a
    /// field-appropriate label and arrow (e.g. "Newest First" / "Oldest First" for
    /// a date field, "A to Z" / "Z to A" for the title). The first is the default.
    static func directions(for field: QuestionSortField) -> [(sort: QuestionSort, label: String, systemImage: String)] {
        switch field {
        case .lastUsed:
            [(.lastUsedDesc, "Newest First", "arrow.down"), (.lastUsedAsc, "Oldest First", "arrow.up")]
        case .used:
            [(.usedDesc, "Most Used", "arrow.down"), (.usedAsc, "Least Used", "arrow.up")]
        case .title:
            [(.titleAsc, "A to Z", "arrow.down"), (.titleDesc, "Z to A", "arrow.up")]
        }
    }

    /// Switching to `field` while keeping the current direction slot (so toggling
    /// the field doesn't reset newest↔oldest).
    func withField(_ newField: QuestionSortField) -> QuestionSort {
        let slot = Self.directions(for: field).firstIndex { $0.sort == self } ?? 0
        let options = Self.directions(for: newField)
        return options[min(slot, options.count - 1)].sort
    }
}

/// The field a ``QuestionSort`` orders by. Pairs with a direction to form the full
/// sort, so the Sort menu can offer field and direction as two sections (à la the
/// Passwords app) rather than one list of combined options.
enum QuestionSortField: String, CaseIterable, Identifiable {
    case lastUsed
    case used
    case title

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastUsed: "Last Used"
        case .used: "Times Used"
        case .title: "Title"
        }
    }

    var systemImage: String {
        switch self {
        case .lastUsed: "clock"
        case .used: "chart.bar"
        case .title: "textformat"
        }
    }
}

/// The Sort menu's contents, shared by the Questions toolbar button and the
/// Question menu's "Sort By" command so they stay in lockstep. Two inline radio
/// sections — sort field, then direction — mirroring the Passwords app.
struct QuestionSortMenuContent: View {
    @Binding var sort: QuestionSort

    var body: some View {
        Picker("Sort By", selection: Binding(get: { sort.field }, set: { sort = sort.withField($0) })) {
            ForEach(QuestionSortField.allCases) { field in
                Label(field.label, systemImage: field.systemImage).tag(field)
            }
        }
        .pickerStyle(.inline)

        Picker("Order", selection: $sort) {
            ForEach(QuestionSort.directions(for: sort.field), id: \.sort) { option in
                Label(option.label, systemImage: option.systemImage).tag(option.sort)
            }
        }
        .pickerStyle(.inline)
    }
}

extension Question {
    /// Title to display, falling back to `#id` when a question has no title.
    var displayTitle: String {
        title.isEmpty ? "#\(id)" : title
    }
}
