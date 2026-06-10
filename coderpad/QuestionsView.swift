//
//  QuestionsView.swift
//  coderpad
//

import SwiftUI

struct QuestionsView: View {
    let client: CoderPadClient
    @Environment(\.orgDirectory) private var directory
    @Environment(\.scenePhase) private var scenePhase
    @State private var accounts = AccountsStore.shared
    @State private var cache = QuestionsCacheStore.shared
    @State private var questions: [Question] = []

    private static let refreshInterval: Duration = .seconds(90)
    @State private var isLoading = false
    @State private var error: Error?
    @State private var selection: Question?
    @State private var search = ""
    @State private var languageFilter: String? = nil
    @State private var ownerFilter: String? = nil
    @State private var takeHomeFilter: String? = nil
    @State private var draftFilter: String? = nil
    @State private var lastFetched: Date?
    @State private var showCreate = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 360, ideal: 440, max: 620)
        } detail: {
            if let selection {
                QuestionDetailView(client: client, question: selection)
                    .id(selection.id)
            } else {
                ContentUnavailableView("Select a question",
                                       systemImage: "questionmark.bubble",
                                       description: Text("Pick one to view details."))
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .createQuestionRequested)) { _ in
            showCreate = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadRequested)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .questionsSearchRequested)) { note in
            if let q = note.object as? String { search = q }
        }
    }

    private var filtered: [Question] {
        let lowered = search.lowercased()
        return questions.filter { q in
            (languageFilter == nil || (q.language ?? "").lowercased() == languageFilter) &&
            (ownerFilter == nil || q.ownerEmail == ownerFilter) &&
            (takeHomeFilter == nil
             || (takeHomeFilter == "yes" && q.takeHome == true)
             || (takeHomeFilter == "no" && q.takeHome != true)) &&
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

    private var availableLanguages: [String] {
        Array(Set(questions.compactMap { $0.language?.lowercased() }).filter { !$0.isEmpty }).sorted()
    }
    private var availableOwners: [String] {
        Array(Set(questions.map { $0.ownerEmail }).filter { !$0.isEmpty }).sorted()
    }

    private var activeFilterCount: Int {
        [languageFilter, ownerFilter, takeHomeFilter, draftFilter].compactMap { $0 }.count
    }

    private var sidebar: some View {
        Group {
            if isLoading && questions.isEmpty {
                ProgressView("Loading questions…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                APIErrorView(error: error) { Task { await reload() } }
            } else {
                VStack(spacing: 0) {
                    PaneTitle(
                        title: "Questions",
                        subtitle: lastFetched.map { "Updated \($0.formatted(.relative(presentation: .named)))" }
                    )
                    InlineSearchField(query: $search, prompt: "Search title, author…")
                        .padding(.horizontal, Spacing.paneH)
                        .padding(.bottom, 8)
                    filterBar
                    Divider()
                    List(filtered, selection: $selection) { q in
                        NavigationLink(value: q) {
                            QuestionRow(question: q)
                        }
                    }
                    .listStyle(.inset)
                    .refreshable { await reload() }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { showCreate = true } label: {
                    Label("New Question", systemImage: "plus")
                }
                .disabled(client.apiKey.isEmpty)
            }
            ToolbarItem {
                Button { Task { await reload() } } label: {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isLoading)
            }
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
                                     formatter: { directory.display($0) })
                FilterChipMenu(title: "Take-home", icon: "house",
                               selected: $takeHomeFilter, options: ["yes", "no"],
                               formatter: { $0.capitalized })
                FilterChipMenu(title: "Status", icon: "doc.badge.ellipsis",
                               selected: $draftFilter, options: ["draft", "published"],
                               formatter: { $0.capitalized })
                if activeFilterCount > 0 {
                    Button(role: .destructive) {
                        languageFilter = nil; ownerFilter = nil
                        takeHomeFilter = nil; draftFilter = nil
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
        }
    }

    private func reload() async {
        guard !client.apiKey.isEmpty else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched = try await client.listQuestions()
            let sorted = fetched.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            questions = sorted
            if let id = accounts.currentAccountID {
                cache.set(id, questions: sorted)
            }
            lastFetched = Date()
        } catch {
            self.error = error
        }
    }
}

private struct QuestionsTaskKey: Hashable {
    let apiKey: String
    let phase: ScenePhase
}

private struct QuestionRow: View {
    let question: Question

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarCircle(label: question.ownerEmail, diameter: 30, tint: .indigo)
            VStack(alignment: .leading, spacing: 4) {
                Text(question.title.isEmpty ? "#\(question.id)" : question.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let lang = question.language, !lang.isEmpty {
                        Chip(text: lang.languageDisplayName, systemImage: lang.languageSymbol, tint: lang.languageColor)
                    }
                    if question.takeHome == true {
                        Chip(text: "Take-home", systemImage: "house", tint: .pink)
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
        }
        .padding(.vertical, 4)
    }
}

struct QuestionDetailView: View {
    let client: CoderPadClient
    let question: Question
    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var deleteError: String?

    var body: some View {
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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarCircle(label: question.ownerEmail, diameter: 48, tint: .indigo)
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.title.isEmpty ? "Untitled Question" : question.title)
                        .font(.title.bold())
                    if let author = question.authorName {
                        Text("by \(author)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    EmailLink(email: question.ownerEmail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Button { showEdit = true } label: { Label("Edit", systemImage: "pencil") }
                        .help("Edit question")
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete question")
                    .accessibilityLabel("Delete question")
                }
            }
            HStack(spacing: 6) {
                if let lang = question.language, !lang.isEmpty {
                    Chip(text: lang.languageDisplayName, systemImage: lang.languageSymbol, tint: lang.languageColor)
                }
                if let type = question.padType, !type.isEmpty {
                    Chip(text: type, systemImage: "tag")
                }
                if question.takeHome == true {
                    Chip(text: "Take-home", systemImage: "house", tint: .pink)
                }
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
}

// MARK: - Question Create / Edit sheets

private let padTypeOptions = ["live", "take-home"]

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
                    ForEach(padTypeOptions, id: \.self) { Text($0.capitalized).tag($0) }
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
                    ForEach(padTypeOptions, id: \.self) { Text($0.capitalized).tag($0) }
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
