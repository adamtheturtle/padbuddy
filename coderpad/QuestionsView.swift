//
//  QuestionsView.swift
//  coderpad
//

import SwiftUI
import AppKit

struct QuestionsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) private var directory
    @Environment(\.scenePhase) private var scenePhase
    @State private var accounts = AccountsStore.shared
    @State private var nav = AppNavigation.shared
    @State private var cache = QuestionsCacheStore.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    @State private var questions: [Question] = []

    @State private var isLoading = false
    @State private var error: Error?
    @Binding var selection: Question?
    @State private var search = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var languageFilter: String? = nil
    @State private var ownerFilter: String? = nil
    @State private var typeFilter: String? = nil
    @State private var draftFilter: String? = nil
    @State private var favoritesOnly = false
    @State private var sort: QuestionSort = .lastUsedDesc
    @State private var showCreate = false
    @State private var savedSearches = SavedSearchStore.shared
    @State private var showSaveSearch = false
    @State private var saveSearchName = ""
    @State private var isSuggestingName = false
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
            await periodicReload(interval: { GeneralSettings.refreshInterval }) {
                await reload()
            }
        }
        .sheet(isPresented: $showCreate) {
            NewQuestionSheet(client: client) { created in
                questions.insert(created, at: 0)
                selection = created
                showCreate = false
            } onCancel: { showCreate = false }
        }
        .sheet(isPresented: $showSaveSearch) {
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
        .task {
            for await q in NotificationCenter.default.notifications(named: .questionUpdated)
                .compactMap({ $0.object as? Question }) {
                if let i = questions.firstIndex(where: { $0.id == q.id }) {
                    questions[i] = q
                    if selection?.id == q.id { selection = q }
                }
            }
        }
        .task {
            for await id in NotificationCenter.default.notifications(named: .questionDeleted)
                .compactMap({ $0.object as? Int }) {
                questions.removeAll { $0.id == id }
                if selection?.id == id { selection = nil }
            }
        }
        .onAppear { applyPendingRequest() }
        .onChange(of: nav.questionsRequest) { _, _ in applyPendingRequest() }
        // A favorite tapped in the sidebar may arrive before the list has loaded;
        // resolve the deferred selection as soon as the questions land.
        .onChange(of: questions) { _, _ in resolvePendingSelection() }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .reloadRequested) {
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

    private var filtered: [Question] {
        let lowered = search.lowercased()
        let favoriteIDs = favoritesOnly ? favoriteIDSet : nil
        return questions.filter { q in
            (favoriteIDs == nil || favoriteIDs!.contains(q.id)) &&
            (languageFilter == nil || (q.language ?? "").lowercased() == languageFilter) &&
            (ownerFilter == nil || q.ownerEmail == ownerFilter) &&
            (typeFilter == nil || q.interviewType.rawValue == typeFilter) &&
            (draftFilter == nil
             || (draftFilter == "draft" && q.isDraft == true)
             || (draftFilter == "published" && q.isDraft != true)) &&
            (lowered.isEmpty
             || q.title.lowercased().contains(lowered)
             || q.ownerEmail.lowercased().contains(lowered)
             || (q.language ?? "").lowercased().contains(lowered)
             || (q.authorName ?? "").lowercased().contains(lowered))
        }
    }

    /// The current account's favorite question ids, as a set for quick membership
    /// tests in filtering, sorting, and row decoration.
    private var favoriteIDSet: Set<Int> {
        Set(favorites.favorites(account: accounts.currentAccountID))
    }

    /// Filtered questions arranged by the active sort, with favorites pinned to the
    /// top. "Last used" is backed by `updatedAt` — the only per-question recency
    /// signal the API exposes. Favorites float up (keeping their relative sort
    /// order within the group) so a frequently used question stays a glance away,
    /// except when already filtering to favorites only, where pinning is moot.
    private var sorted: [Question] {
        let items = filtered
        let ordered: [Question]
        switch sort {
        case .titleAsc:
            ordered = items.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .titleDesc:
            ordered = items.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedDescending }
        case .lastUsedDesc:
            ordered = items.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .lastUsedAsc:
            ordered = items.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        }
        let favoriteIDs = favoriteIDSet
        guard !favoritesOnly, !favoriteIDs.isEmpty else { return ordered }
        return ordered.filter { favoriteIDs.contains($0.id) }
            + ordered.filter { !favoriteIDs.contains($0.id) }
    }

    private var availableLanguages: [String] {
        Array(Set(questions.compactMap { $0.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }
    private var availableOwners: [String] {
        Array(Set(questions.map { $0.ownerEmail }).filter { !$0.isEmpty }).sorted()
    }

    private var activeFilterCount: Int {
        [languageFilter, ownerFilter, typeFilter, draftFilter].compactMap { $0 }.count
    }

    private var sidebar: some View {
        Group {
            if isLoading && questions.isEmpty {
                ProgressView("Loading questions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, questions.isEmpty {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    PaneTitle(title: "Questions")
                    InlineSearchField(query: $search, prompt: "Search title, author…",
                                      focused: $searchFieldFocused)
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.bottom, 8)
                    savedSearchesBar
                    filterBar
                    Divider()
                    List(selection: $selection) {
                        ForEach(sorted) { q in
                            QuestionRow(question: q, isFavorite: favoriteIDSet.contains(q.id),
                                        onToggleFavorite: { toggleFavorite(q) })
                                .tag(q)
                                .contextMenu { questionContextMenu(q) }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    favoriteSwipeButton(q)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        // Same path as the context menu and detail
                                        // "New Pad" button: select the question, then
                                        // let its detail pane create and open the pad.
                                        selection = q
                                        nav.createPadForQuestionID = q.id
                                    } label: {
                                        Label("New Pad", systemImage: "doc.badge.plus")
                                    }
                                    .tint(.accentColor)
                                }
                        }
                    }
                    .listStyle(.inset)
                    .macPullToRefresh { await reload() }
                    // Scene-scoped, mirroring PadsView: the Question menu commands
                    // stay enabled whenever this window is frontmost and a question
                    // is selected, not only while the list holds keyboard focus.
                    .focusedSceneValue(\.focusedQuestion, selection)
                }
            }
        }
        .focusedSceneValue(\.findAction, FindAction(id: "questions") { searchFieldFocused = true })
        .toolbar(id: "questions.toolbar") {
            ToolbarItem(id: "sort") {
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
            ToolbarItem(id: "reload") {
                ReloadToolbarButton(isLoading: isLoading) { Task { await reload() } }
            }
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "new", placement: .primaryAction) {
                Button { showCreate = true } label: {
                    Label("New Question", systemImage: "plus")
                }
                .help("Create a new question (⇧⌘N)")
                .accessibilityLabel("New Question")
                .disabled(client.apiKey.isEmpty)
            }
        }
    }

    /// Right-click actions for a question row. Actions that need the detail pane's
    /// machinery (its sheets and confirmations) select the question first, then
    /// route the request through `AppNavigation` — the same pattern as "New Pad
    /// from Question" — so the detail view performs them with its existing UI.
    @ViewBuilder
    private func questionContextMenu(_ q: Question) -> some View {
        Button {
            // Mirror the detail view's "New Pad" button: select the question so
            // its detail pane shows, then let that pane create the pad and open
            // it inline.
            selection = q
            nav.createPadForQuestionID = q.id
        } label: {
            Label("New Pad from Question", systemImage: "plus.rectangle.on.rectangle")
        }
        favoriteToggleButton(q)
        Button {
            selection = q
            nav.editQuestionID = q.id
        } label: {
            Label("Edit Question…", systemImage: "pencil")
        }
        Divider()
        Button {
            copyToPasteboard(q.displayTitle)
        } label: {
            Label("Copy Title", systemImage: "doc.on.doc")
        }
        Button {
            ownerFilter = q.ownerEmail
        } label: {
            Label("Show Questions from \(directory.display(q.ownerEmail))", systemImage: "person")
        }
        if let lang = q.language, !lang.isEmpty {
            Button {
                languageFilter = lang.lowercased()
            } label: {
                Label("Show \(lang.languageDisplayName) Questions", systemImage: "chevron.left.slash.chevron.right")
            }
        }
        Divider()
        Button(role: .destructive) {
            selection = q
            nav.deleteQuestionID = q.id
        } label: {
            Label("Delete Question…", systemImage: "trash")
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Context-menu entry that stars or unstars a question. Favorites pin the
    /// question to the top of the list and lead the menu bar's "New Pad from
    /// Question" submenu, so a frequently used question is quick to reach.
    @ViewBuilder
    private func favoriteToggleButton(_ q: Question) -> some View {
        let isFavorite = favoriteIDSet.contains(q.id)
        Button {
            toggleFavorite(q)
        } label: {
            Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                  systemImage: isFavorite ? "star.slash" : "star")
        }
    }

    /// Leading swipe action mirroring the favorite context-menu entry.
    @ViewBuilder
    private func favoriteSwipeButton(_ q: Question) -> some View {
        let isFavorite = favoriteIDSet.contains(q.id)
        Button {
            toggleFavorite(q)
        } label: {
            Label(isFavorite ? "Unfavorite" : "Favorite",
                  systemImage: isFavorite ? "star.slash" : "star")
        }
        .tint(.yellow)
    }

    private func toggleFavorite(_ q: Question) {
        guard let account = accounts.currentAccountID else { return }
        favorites.toggle(q.id, account: account)
        // Unstarring the last favorite hides the Favorites chip, so drop the
        // filter too — otherwise it would strand the list on an empty result with
        // no visible control to turn it back off.
        if favoritesOnly && favoriteIDSet.isEmpty {
            favoritesOnly = false
        }
    }

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChipMenu(title: "Language", icon: "chevron.left.slash.chevron.right",
                               selected: $languageFilter, options: availableLanguages,
                               formatter: { $0.languageDisplayName })
                SearchableFilterChip(title: "Owner", icon: "person",
                                     selected: $ownerFilter, options: availableOwners,
                                     formatter: { directory.display($0) },
                                     meEmail: accounts.currentAccount?.userEmail)
                FilterChipMenu(title: "Type", icon: "tag",
                               selected: $typeFilter,
                               options: InterviewType.allCases.map(\.rawValue),
                               formatter: { InterviewType(rawValue: $0)?.label ?? $0.capitalized })
                FilterChipMenu(title: "Status", icon: "doc.badge.ellipsis",
                               selected: $draftFilter, options: ["draft", "published"],
                               formatter: { $0.capitalized })
                if activeFilterCount > 0 || !search.isEmpty {
                    Button {
                        saveSearchName = ""
                        showSaveSearch = true
                    } label: {
                        Label("Save…", systemImage: "bookmark")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                if activeFilterCount > 0 {
                    Button(role: .destructive) {
                        languageFilter = nil; ownerFilter = nil
                        typeFilter = nil; draftFilter = nil
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .measuresFilterBarWidth()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// Built-in chips shown ahead of the user's saved searches. "My Questions"
    /// appears only when the account knows its user's email; "Drafts" filters to
    /// unpublished questions.
    private var defaultSearches: [DefaultSearch] {
        var result: [DefaultSearch] = []
        if let me = accounts.currentAccount?.userEmail, !me.isEmpty {
            result.append(DefaultSearch(id: "my-questions", icon: "person.fill",
                                        search: NamedSearch(name: "My Questions", ownerFilter: me)))
        }
        result.append(DefaultSearch(id: "drafts", icon: "doc.badge.ellipsis",
                                    search: NamedSearch(name: "Drafts", draftFilter: "draft")))
        return result
    }

    @ViewBuilder
    private var savedSearchesBar: some View {
        let saved = savedSearches.searches(account: accounts.currentAccountID, kind: .questions)
        let defaults = defaultSearches
        let hasFavorites = !favoriteIDSet.isEmpty
        if hasFavorites || !defaults.isEmpty || !saved.isEmpty {
            // A wrapping flow layout rather than a horizontal scroll, so the chips
            // reflow onto extra lines as the pane narrows instead of clipping a
            // long saved-search name off the trailing edge.
            FlowLayout(spacing: 6, lineSpacing: 6) {
                // A toggle, unlike the recall chips beside it: tapping filters the
                // list to starred questions and tapping again clears it. Shown only
                // once at least one question is starred.
                if hasFavorites {
                    SavedSearchChip(name: "Favorites", systemImage: "star.fill",
                                    isActive: favoritesOnly) {
                        favoritesOnly.toggle()
                    }
                }
                ForEach(defaults) { item in
                    SavedSearchChip(name: item.search.name, systemImage: item.icon,
                                    isActive: isActiveSearch(item.search)) {
                        apply(item.search)
                    }
                }
                ForEach(saved) { item in
                    SavedSearchChip(name: item.name, isActive: isActiveSearch(item)) {
                        apply(item)
                    } onDelete: {
                        if let account = accounts.currentAccountID {
                            savedSearches.remove(id: item.id, account: account, kind: .questions)
                        }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 6)
        }
    }

    /// A sparkle button that fills the name field with an on-device suggestion
    /// built from the active filters. Shown only when the model is available; the
    /// field stays fully editable and the user opts in per save.
    @ViewBuilder
    private var suggestNameButton: some View {
        Button(action: suggestName) {
            if isSuggestingName {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "sparkles")
            }
        }
        .buttonStyle(.borderless)
        .disabled(isSuggestingName)
        .help("Suggest a name from the current filters")
        .accessibilityLabel("Suggest a name")
    }

    private func suggestName() {
        let captured = captureCurrentSearch(named: "")
        isSuggestingName = true
        Task {
            let suggestion = await SavedSearchNamer.suggestName(for: captured)
            isSuggestingName = false
            if let suggestion { saveSearchName = suggestion }
        }
    }

    private func commitSavedSearch() {
        // Return in the text field fires `onSubmit` and the default-action button can
        // also fire; guarding on the still-open sheet keeps a single keypress from
        // saving the search twice.
        guard showSaveSearch else { return }
        let trimmed = String(saveSearchName.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(NamedSearch.maxNameLength))
        guard !trimmed.isEmpty, let account = accounts.currentAccountID else { return }
        savedSearches.add(captureCurrentSearch(named: trimmed), account: account, kind: .questions)
        showSaveSearch = false
    }

    private func apply(_ saved: NamedSearch) {
        search = saved.search
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        typeFilter = saved.typeFilter
        draftFilter = saved.draftFilter
    }

    /// Whether the list's live filters exactly match `saved`, so its chip can show
    /// as active. Mirrors `apply` field-for-field — including `draftFilter`, which
    /// the question list has but pads don't — so editing any filter drops the
    /// highlight immediately.
    private func isActiveSearch(_ saved: NamedSearch) -> Bool {
        search == saved.search &&
        languageFilter == saved.languageFilter &&
        ownerFilter == saved.ownerFilter &&
        typeFilter == saved.typeFilter &&
        draftFilter == saved.draftFilter
    }

    private func captureCurrentSearch(named name: String) -> NamedSearch {
        NamedSearch(
            name: name, search: search,
            languageFilter: languageFilter, ownerFilter: ownerFilter,
            typeFilter: typeFilter, draftFilter: draftFilter
        )
    }

    private func reload() async {
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

private struct QuestionsTaskKey: Hashable {
    let apiKey: String
    let phase: ScenePhase
}

/// Sort orders offered for the Questions list. "Last used" is backed by the
/// question's `updatedAt` timestamp — the API exposes no distinct last-used date.
enum QuestionSort: String, CaseIterable, Identifiable {
    case lastUsedDesc
    case lastUsedAsc
    case titleAsc
    case titleDesc

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastUsedDesc: "Last used (newest first)"
        case .lastUsedAsc: "Last used (oldest first)"
        case .titleAsc: "Title (A-Z)"
        case .titleDesc: "Title (Z-A)"
        }
    }
}

extension Question {
    /// Title to display, falling back to `#id` when a question has no title.
    var displayTitle: String { title.isEmpty ? "#\(id)" : title }
}

private struct QuestionRow: View {
    let question: Question
    var isFavorite: Bool = false
    var onToggleFavorite: () -> Void = {}

    @State private var hovered = false

    var body: some View {
        // The text/metadata block keeps its top alignment (title, chips, and the
        // last-used date all read from the top), while the favorite star is
        // centered against the row's full height as a row-level action distinct
        // from the metadata.
        HStack(alignment: .center, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let lang = question.language, !lang.isEmpty {
                            Chip(text: lang.languageDisplayName, systemImage: lang.languageSymbol, tint: lang.languageColor)
                        }
                        if question.interviewType == .takeHome {
                            InterviewType.takeHome.chip
                        }
                        if let used = question.used, used > 0 {
                            Chip(text: "Used \(used)×", systemImage: "chart.bar", tint: .blue)
                        }
                        if question.isDraft == true {
                            Chip(text: "Draft", systemImage: "doc.badge.ellipsis", tint: .orange)
                        }
                    }
                    if let author = question.authorName {
                        Text(author).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let lastUsed = question.updatedAt {
                    Text(lastUsed.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("Last used \(lastUsed.formatted(date: .abbreviated, time: .shortened))")
                        .accessibilityLabel("Last used \(lastUsed.formatted(.relative(presentation: .named)))")
                }
            }
            favoriteButton
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    /// Inline favorite toggle, à la Mail's flag: always shown (filled) once the
    /// question is starred, and revealed faintly on hover otherwise so the resting
    /// list stays uncluttered. The button always occupies its slot — only opacity
    /// changes on hover — so rows don't shift as the pointer moves down the list.
    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(isFavorite ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .opacity(isFavorite || hovered ? 1 : 0)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(question.displayTitle) from Favorites"
                                       : "Add \(question.displayTitle) to Favorites")
    }
}

struct QuestionDetailView: View {
    let client: CoderPadClient
    let question: Question
    @Environment(\.openWindow) private var openWindow
    @State private var nav = AppNavigation.shared
    @State private var accounts = AccountsStore.shared
    @State private var favorites = FavoriteQuestionsStore.shared
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?
    @State private var isCreatingPad = false
    @State private var createPadError: String?
    @State private var showBrowser = false
    @State private var createdPadURL: URL?

    var body: some View {
        Group {
            if showBrowser, let url = createdPadURL {
                padBrowser(url: url)
            } else {
                detailScroll
            }
        }
        .navigationTitle(question.title.isEmpty ? "#\(question.id)" : question.title)
        // Detail-column actions live in the unified window toolbar rather than in
        // the content header: there they float on the system Liquid Glass layer
        // automatically, and the header stays free for identity and metadata. A
        // leading spacer separates them from the Questions list's own toolbar
        // items (Sort, Reload, New Question) so "New Pad" doesn't read as a
        // sibling of "New Question".
        .toolbar(id: "question.detail.toolbar") {
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed)
            }
            ToolbarItem(id: "favoriteQuestion", placement: .primaryAction) {
                Button { toggleFavorite() } label: {
                    Label(isFavorite ? "Favorited" : "Favorite",
                          systemImage: isFavorite ? "star.fill" : "star")
                }
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            ToolbarItem(id: "newPad", placement: .primaryAction) {
                Button { Task { await createPad() } } label: {
                    if isCreatingPad {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("New Pad", systemImage: "doc.badge.plus")
                    }
                }
                .disabled(isCreatingPad)
                .help("Create a new interview pad from this question")
                .accessibilityLabel("New Pad")
            }
            ToolbarItem(id: "editQuestion", placement: .primaryAction) {
                Button { showEdit = true } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit question")
            }
            ToolbarItem(id: "deleteQuestion", placement: .primaryAction) {
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete question")
                .accessibilityLabel("Delete question")
            }
        }
        .sheet(isPresented: $showEdit) {
            EditQuestionSheet(client: client, original: question) { updated in
                NotificationCenter.default.post(name: .questionUpdated, object: updated)
                showEdit = false
            } onCancel: { showEdit = false }
        }
        .confirmationDialog("Delete \(question.title.isEmpty ? "this question" : question.title)?",
                             isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { Task { await deleteQuestion() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Couldn’t create pad",
               isPresented: Binding(get: { createPadError != nil },
                                    set: { if !$0 { createPadError = nil } })) {
            Button("OK", role: .cancel) { createPadError = nil }
        } message: {
            if let createPadError { Text(createPadError) }
        }
        .onAppear {
            consumePendingPadCreation()
            consumePendingEdit()
            consumePendingDelete()
        }
        .onChange(of: nav.createPadForQuestionID) { _, _ in consumePendingPadCreation() }
        .onChange(of: nav.editQuestionID) { _, _ in consumePendingEdit() }
        .onChange(of: nav.deleteQuestionID) { _, _ in consumePendingDelete() }
    }

    private var detailScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metaCards
                if let description = question.description, !description.isEmpty {
                    descriptionCard(title: "Description", body: description)
                }
                if !question.candidateInstructions.isEmpty {
                    instructionsCard
                }
                if !question.testCases.isEmpty {
                    testCasesCard
                }
                if !question.customFiles.isEmpty {
                    filesCard
                }
                if let solution = question.solution, !solution.isEmpty {
                    descriptionCard(title: "Solution", body: solution)
                }
            }
            .padding(.horizontal, Spacing.paneH)
            .padding(.top, Spacing.paneV)
            .padding(.bottom, Spacing.paneV)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The freshly created pad shown in the in-pane browser, mirroring
    /// `PadDetailView` so creating a pad here behaves like opening one there:
    /// inline by default, with buttons to break out to a separate window or
    /// the default browser.
    private func padBrowser(url: URL) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    showBrowser = false
                } label: {
                    Label("Back to Question", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button {
                    openWindow(id: "pad-browser", value: url)
                } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .help("Open in separate window")
                .buttonStyle(.borderless)
                .accessibilityLabel("Open in separate window")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .floatingGlass(in: Rectangle(), fallback: .thinMaterial)
            Divider()
            PadBrowserView(url: url)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Actions now live in the window toolbar, so the header only carries
            // identity and the metadata chips below.
            headerIdentity
            HStack(spacing: 6) {
                if let lang = question.language, !lang.isEmpty {
                    Chip(text: lang.languageDisplayName, systemImage: lang.languageSymbol, tint: lang.languageColor)
                }
                question.interviewType.chip
                if question.shared == true {
                    Chip(text: "Shared", systemImage: "person.2", tint: .blue)
                }
                if question.testCasesEnabled == true {
                    Chip(text: "Test cases", systemImage: "checkmark.seal", tint: .teal)
                }
                if question.isDraft == true {
                    Chip(text: "Draft", systemImage: "doc.badge.ellipsis", tint: .orange)
                }
            }
        }
    }

    private var headerIdentity: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.title.isEmpty ? "Untitled Question" : question.title)
                    .font(.title.bold())
                    .lineLimit(2)
                if let author = question.authorName {
                    Text("by \(author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                EmailLink(email: question.ownerEmail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var metaCards: some View {
        // An adaptive grid rather than a fixed HStack: three equal tiles fit on
        // one row in a wide pane, but reflow onto extra rows as it narrows.
        // A plain HStack instead overflows the pane — clipping the trailing tile
        // and hyphenating its label (CRE-ATED / UP-DATED) — once the tiles can't
        // all fit at their minimum width.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                  alignment: .leading, spacing: 12) {
            if let used = question.used {
                StatTile(title: "Times used", value: "\(used)", systemImage: "chart.bar.fill", tint: .blue)
            }
            if let createdAt = question.createdAt {
                StatTile(title: "Created", value: createdAt.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "calendar.badge.plus", tint: .teal)
            }
            if let updatedAt = question.updatedAt {
                StatTile(title: "Updated", value: updatedAt.formatted(date: .abbreviated, time: .omitted),
                         systemImage: "clock.arrow.circlepath", tint: .orange)
            }
        }
    }

    private var instructionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Candidate Instructions", systemImage: "text.book.closed")
                ForEach(Array(question.candidateInstructions.enumerated()), id: \.offset) { _, item in
                    MarkdownText(item.instructions)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The question's test cases, shown to an interviewer in full. The candidate
    /// only sees the cases marked `visible`, so hidden ones carry a badge to make
    /// that distinction clear when reviewing.
    private var testCasesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Test Cases", systemImage: "checkmark.seal")
                ForEach(question.testCases) { testCase in
                    testCaseRow(testCase)
                    if testCase.id != question.testCases.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func testCaseRow(_ testCase: QuestionTestCase) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                testCaseLine(label: "Input", value: argumentsDisplay(testCase.arguments))
                testCaseLine(label: "Expected", value: testCase.returnValue ?? "—")
            }
            Spacer(minLength: 8)
            if testCase.visible == false {
                Chip(text: "Hidden", systemImage: "eye.slash", tint: .gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func testCaseLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The API returns each argument as its own already-formatted string (e.g. a
    /// quoted string or a JSON literal), so join them into a call-style list.
    private func argumentsDisplay(_ arguments: [String]?) -> String {
        guard let arguments, !arguments.isEmpty else { return "—" }
        return arguments.joined(separator: ", ")
    }

    /// The question's attached custom files. The API exposes only metadata (name,
    /// description, size) for these, not their contents, so this is a manifest of
    /// what's bundled rather than a viewer.
    private var filesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Files", systemImage: "doc.on.doc")
                ForEach(Array(question.customFiles.enumerated()), id: \.offset) { index, file in
                    fileRow(file)
                    if index != question.customFiles.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fileRow(_ file: QuestionCustomFile) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(fileName(file))
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
                if let description = file.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let size = file.filesize, !size.isEmpty {
                Text(size)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A display name for a custom file: its filename, falling back to its title,
    /// then a generic placeholder when the API supplies neither.
    private func fileName(_ file: QuestionCustomFile) -> String {
        if let filename = file.filename, !filename.isEmpty { return filename }
        if let title = file.title, !title.isEmpty { return title }
        return "Untitled file"
    }

    private func descriptionCard(title: String, body: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, systemImage: "doc.text")
                MarkdownText(body)
                    .font(.callout)
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func deleteQuestion() async {
        do {
            try await client.deleteQuestion(id: question.id)
            NotificationCenter.default.post(name: .questionDeleted, object: question.id)
        } catch {
            deleteError = error.localizedDescription
        }
    }

    /// Whether the displayed question is a favorite of the current account, so the
    /// toolbar star can reflect and toggle its state.
    private var isFavorite: Bool {
        favorites.isFavorite(question.id, account: accounts.currentAccountID)
    }

    private func toggleFavorite() {
        guard let account = accounts.currentAccountID else { return }
        favorites.toggle(question.id, account: account)
    }

    /// Honors a "New Pad from Question" request routed via `AppNavigation` (e.g.
    /// from the Questions list's context menu): create the pad and open it inline,
    /// exactly as the in-pane "New Pad" button does.
    private func consumePendingPadCreation() {
        guard nav.createPadForQuestionID == question.id else { return }
        nav.createPadForQuestionID = nil
        Task { await createPad() }
    }

    /// Honors an "Edit Question" request routed via `AppNavigation` from the list's
    /// context menu by presenting the same edit sheet as the in-pane Edit button.
    private func consumePendingEdit() {
        guard nav.editQuestionID == question.id else { return }
        nav.editQuestionID = nil
        showEdit = true
    }

    /// Honors a "Delete Question" request from the list's context menu by showing
    /// the same delete confirmation as the in-pane Delete button — never deleting
    /// without that confirmation step.
    private func consumePendingDelete() {
        guard nav.deleteQuestionID == question.id else { return }
        nav.deleteQuestionID = nil
        showDeleteConfirm = true
    }

    private func createPad() async {
        isCreatingPad = true
        defer { isCreatingPad = false }
        do {
            let pad = try await client.createPad(.fromQuestion(question))
            if let url = pad.webURL {
                createdPadURL = url
                showBrowser = true
            }
        } catch {
            createPadError = error.localizedDescription
        }
    }
}

// MARK: - Question Create / Edit sheets

private let padTypeOptions = InterviewType.allCases.map(\.rawValue)
private func padTypeLabel(_ raw: String) -> String { InterviewType(rawValue: raw)?.label ?? raw.capitalized }

private struct NewQuestionSheet: View {
    let client: CoderPadClient
    let onCreated: (Question) -> Void
    let onCancel: () -> Void

    @Environment(\.orgDirectory) private var directory
    @State private var title = ""
    @State private var language = "python3"
    /// Set once the user picks a language themselves, so a late-arriving org
    /// default doesn't overwrite their choice.
    @State private var languageEdited = false
    @State private var description = ""
    @State private var instructions = ""
    @State private var solution = ""
    @State private var padType = "live"
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Question").font(.title3.bold())
            Form {
                TextField("Title", text: $title)
                Picker("Language", selection: languageSelection) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }
                Picker("Type", selection: $padType) {
                    ForEach(padTypeOptions, id: \.self) { Text(padTypeLabel($0)).tag($0) }
                }
                Section("Description") {
                    TextField("", text: $description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Candidate instructions") {
                    TextField("", text: $instructions, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(4...12)
                }
                Section("Solution") {
                    TextField("", text: $solution, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3...12)
                }
            }
            .formStyle(.grouped)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button { Task { await submit() } } label: {
                    if isSubmitting { ProgressView().controlSize(.small) } else { Text("Create") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 540)
        .task { applyOrgDefaultLanguage() }
        .onChange(of: directory.defaultLanguage) { _, _ in applyOrgDefaultLanguage() }
    }

    /// The language picker's binding, marking the choice as user-made so the org
    /// default no longer overrides it.
    private var languageSelection: Binding<String> {
        Binding(get: { language }, set: { language = $0; languageEdited = true })
    }

    /// Pre-select the organization's default language, unless the user has already
    /// chosen one. Driven by `OrgDirectory`, which is loaded app-wide.
    private func applyOrgDefaultLanguage() {
        guard !languageEdited, let def = directory.defaultLanguage, !def.isEmpty else { return }
        language = def
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let body = QuestionCreate(
            title: title,
            language: language,
            description: description.isEmpty ? nil : description,
            solution: solution.isEmpty ? nil : solution,
            takeHome: padType == "take-home",
            padType: padType,
            candidateInstructions: instructions.isEmpty
                ? nil
                : [CandidateInstructionPayload(instructions: instructions, defaultVisible: true)]
        )
        do {
            let q = try await client.createQuestion(body)
            onCreated(q)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EditQuestionSheet: View {
    let client: CoderPadClient
    let original: Question
    let onSaved: (Question) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var language: String
    @State private var description: String
    @State private var instructions: String
    @State private var solution: String
    @State private var padType: String
    @State private var isSubmitting = false
    @State private var error: String?

    init(client: CoderPadClient,
         original: Question,
         onSaved: @escaping (Question) -> Void,
         onCancel: @escaping () -> Void) {
        self.client = client
        self.original = original
        self.onSaved = onSaved
        self.onCancel = onCancel
        _title = State(initialValue: original.title)
        _language = State(initialValue: original.language ?? "python3")
        _description = State(initialValue: original.description ?? "")
        _instructions = State(initialValue: original.candidateInstructions
            .map(\.instructions)
            .joined(separator: "\n\n"))
        _solution = State(initialValue: original.solution ?? "")
        let initialType = original.padType ?? (original.takeHome == true ? "take-home" : "live")
        _padType = State(initialValue: initialType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit Question").font(.title3.bold())
            Text("#\(original.id)").font(.caption.monospaced()).foregroundStyle(.secondary)
            Form {
                TextField("Title", text: $title)
                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) { Text(language.languageDisplayName).tag(language) }
                }
                Picker("Type", selection: $padType) {
                    ForEach(padTypeOptions, id: \.self) { Text(padTypeLabel($0)).tag($0) }
                    if !padTypeOptions.contains(padType) { Text(padType).tag(padType) }
                }
                Section("Description") {
                    TextField("", text: $description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3...8)
                }
                Section("Candidate instructions") {
                    TextField("", text: $instructions, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(4...12)
                }
                Section("Solution") {
                    TextField("", text: $solution, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3...12)
                }
            }
            .formStyle(.grouped)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button { Task { await submit() } } label: {
                    if isSubmitting { ProgressView().controlSize(.small) } else { Text("Save") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        // Send the edited instructions back as a single block so an edit no longer
        // wipes them. An empty field clears them; the original's visibility is kept.
        let body = QuestionUpdate(
            id: original.id,
            title: title,
            language: language,
            description: description.isEmpty ? nil : description,
            solution: solution.isEmpty ? nil : solution,
            takeHome: padType == "take-home",
            padType: padType,
            candidateInstructions: instructions.isEmpty
                ? []
                : [CandidateInstructionPayload(
                    instructions: instructions,
                    defaultVisible: original.candidateInstructions.first?.defaultVisible ?? true)]
        )
        do {
            let q = try await client.updateQuestion(body)
            onSaved(q)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
