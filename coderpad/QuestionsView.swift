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
    @State private var questions: [Question] = []

    private static let refreshInterval: Duration = .seconds(90)
    @State private var isLoading = false
    @State private var error: Error?
    @Binding var selection: Question?
    @State private var search = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var languageFilter: String? = nil
    @State private var ownerFilter: String? = nil
    @State private var typeFilter: String? = nil
    @State private var draftFilter: String? = nil
    @State private var sort: QuestionSort = .lastUsedDesc
    @State private var showCreate = false

    var body: some View {
        sidebar
        .task(id: QuestionsTaskKey(apiKey: client.apiKey, phase: scenePhase)) {
            guard scenePhase == .active else { return }
            if questions.isEmpty, let id = accounts.currentAccountID {
                questions = cache.get(id)
            }
            await periodicReload(interval: Self.refreshInterval) {
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
        .onReceive(NotificationCenter.default.publisher(for: .questionUpdated)) { note in
            if let q = note.object as? Question,
               let i = questions.firstIndex(where: { $0.id == q.id }) {
                questions[i] = q
                if selection?.id == q.id { selection = q }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .questionDeleted)) { note in
            if let id = note.object as? Int {
                questions.removeAll { $0.id == id }
                if selection?.id == id { selection = nil }
            }
        }
        .onAppear { applyPendingRequest() }
        .onChange(of: nav.questionsRequest) { _, _ in applyPendingRequest() }
        .onReceive(NotificationCenter.default.publisher(for: .reloadRequested)) { _ in
            Task { await reload() }
        }
    }

    /// Applies any request queued by `AppNavigation`, then clears it. See the
    /// matching method in `PadsView` for the appear-vs-change rationale.
    private func applyPendingRequest() {
        guard let request = nav.questionsRequest else { return }
        nav.questionsRequest = nil
        if let query = request.search { search = query }
        if request.startCreating { showCreate = true }
    }

    private var filtered: [Question] {
        let lowered = search.lowercased()
        return questions.filter { q in
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

    /// Filtered questions arranged by the active sort. "Last used" is backed by
    /// `updatedAt` — the only per-question recency signal the API exposes.
    private var sorted: [Question] {
        let items = filtered
        switch sort {
        case .titleAsc:
            return items.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .titleDesc:
            return items.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedDescending }
        case .lastUsedDesc:
            return items.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .lastUsedAsc:
            return items.sorted { ($0.updatedAt ?? .distantPast) < ($1.updatedAt ?? .distantPast) }
        }
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
            } else if let error {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    PaneTitle(title: "Questions")
                    HStack(spacing: 8) {
                        InlineSearchField(query: $search, prompt: "Search title, author…",
                                          focused: $searchFieldFocused)
                        paneActions
                    }
                    .padding(.horizontal, Spacing.paneH)
                    .padding(.bottom, 8)
                    filterBar
                    Divider()
                    List(selection: $selection) {
                        ForEach(sorted) { q in
                            QuestionRow(question: q)
                                .tag(q)
                                .contextMenu {
                                    Button {
                                        // Mirror the detail view's "New Pad" button: select the
                                        // question so its detail pane shows, then let that pane
                                        // create the pad and open it inline.
                                        selection = q
                                        nav.createPadForQuestionID = q.id
                                    } label: {
                                        Label("New Pad from Question", systemImage: "plus.rectangle.on.rectangle")
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                    .refreshable { await reload() }
                }
            }
        }
        .focusedSceneValue(\.findAction, FindAction { searchFieldFocused = true })
    }

    private var paneActions: some View {
        HStack(spacing: 2) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(QuestionSort.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort questions")
            .accessibilityLabel("Sort questions")
            Button { showCreate = true } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New Question")
            .accessibilityLabel("New Question")
            .disabled(client.apiKey.isEmpty)
            Button { Task { await reload() } } label: {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Reload")
            .accessibilityLabel("Reload")
            .disabled(isLoading)
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
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            // Render page 1 immediately, then grow the list as later pages stream in.
            // Snapshots arrive sorted updated_at,desc, so rows only append below.
            var fetched: [Question] = []
            for try await snapshot in client.listQuestionsIncrementally() {
                fetched = snapshot
                questions = snapshot
            }
            if let id = accounts.currentAccountID {
                cache.set(id, questions: fetched)
            }
        } catch {
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
        case .titleAsc: "Title (A–Z)"
        case .titleDesc: "Title (Z–A)"
        }
    }
}

extension Question {
    /// Title to display, falling back to `#id` when a question has no title.
    var displayTitle: String { title.isEmpty ? "#\(id)" : title }
}

private struct QuestionRow: View {
    let question: Question

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(label: question.ownerEmail, diameter: 30, tint: .indigo)
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
        .padding(.vertical, 4)
    }
}

struct QuestionDetailView: View {
    let client: CoderPadClient
    let question: Question
    @Environment(\.openWindow) private var openWindow
    @State private var nav = AppNavigation.shared
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
        .onAppear { consumePendingPadCreation() }
        .onChange(of: nav.createPadForQuestionID) { _, _ in consumePendingPadCreation() }
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
            .background(.thinMaterial)
            Divider()
            PadBrowserView(url: url)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarCircle(label: question.ownerEmail, diameter: 48, tint: .indigo)
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
                }
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Button { Task { await createPad() } } label: {
                        if isCreatingPad {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("New Pad", systemImage: "plus.rectangle.on.rectangle")
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isCreatingPad)
                    .help("Create a new interview pad from this question")
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        .help("Edit question")
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete question")
                    .accessibilityLabel("Delete question")
                }
                .fixedSize()
            }
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

    private var metaCards: some View {
        HStack(spacing: 12) {
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

    /// Honors a "New Pad from Question" request routed via `AppNavigation` (e.g.
    /// from the Questions list's context menu): create the pad and open it inline,
    /// exactly as the in-pane "New Pad" button does.
    private func consumePendingPadCreation() {
        guard nav.createPadForQuestionID == question.id else { return }
        nav.createPadForQuestionID = nil
        Task { await createPad() }
    }

    private func createPad() async {
        isCreatingPad = true
        defer { isCreatingPad = false }
        do {
            let pad = try await client.createPad(.fromQuestion(question))
            if let url = URL(string: pad.url) {
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

    @State private var title = ""
    @State private var language = "python3"
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
                Picker("Language", selection: $language) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.languageDisplayName).tag($0) }
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
