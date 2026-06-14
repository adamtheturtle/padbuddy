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
                    selection = created
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
                    // Move to a neighbor before dropping the row so deleting the
                    // open question keeps the detail pane populated. Computed while
                    // `questions` still holds the deleted row.
                    if selection?.id == id { selection = neighborSelection(forDeletedQuestion: id) }
                    questions.removeAll { $0.id == id }
                    // Keep the disk cache and Spotlight index in step; otherwise the
                    // deleted question lingers there until a full reload.
                    cache.removeQuestion(id: id, account: accounts.currentAccountID)
                }
            }
            .onAppear {
                applyPendingRequest()
                publishLiveFilter()
                selectedQuestionID = selection?.id
            }
            // Bridge the lightweight list selection (`selectedQuestionID`) to the
            // `Question` binding the detail pane reads. Each side writes only when the
            // id truly differs, so the two `onChange`s can't ping-pong.
            .onChange(of: selectedQuestionID) { _, newID in
                if selection?.id != newID {
                    selection = newID.flatMap { id in questions.first { $0.id == id } }
                }
            }
            .onChange(of: selection) { _, newValue in
                if selectedQuestionID != newValue?.id { selectedQuestionID = newValue?.id }
            }
            .onChange(of: nav.questionsRequest) { _, _ in applyPendingRequest() }
            // Republish the live filter so the sidebar highlights whichever suggested or
            // saved row is applied, and falls back to the plain "Questions" row the moment
            // any filter is edited. Keyed off a stable digest because a fresh
            // `captureCurrentSearch` carries a new UUID each call and would fire endlessly.
            .onChange(of: filterSignature) { _, _ in publishLiveFilter() }
            // A favorite tapped in the sidebar may arrive before the list has loaded;
            // resolve the deferred selection as soon as the questions land.
            .onChange(of: questions) { _, _ in resolvePendingSelection() }
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
            selection = match
            pendingSelectQuestionID = nil
        } else {
            pendingSelectQuestionID = id
        }
    }

    private func resolvePendingSelection() {
        guard let id = pendingSelectQuestionID,
              let match = questions.first(where: { $0.id == id }) else { return }
        selection = match
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
}

extension Question {
    /// Title to display, falling back to `#id` when a question has no title.
    var displayTitle: String {
        title.isEmpty ? "#\(id)" : title
    }
}
