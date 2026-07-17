//
//  QuestionSheets.swift
//  coderpad
//

import SwiftUI

// MARK: - Question Create / Edit sheets

struct NewQuestionSheet: View {
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
    @State private var selectedSection: QuestionDraftSection = .instructions
    @State private var padType = "live"
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var draftPrompt = ""
    @State private var isDrafting = false

    var body: some View {
        sheetContent
            .interactiveDismissDisabled(isSubmitting)
            .task { applyOrgDefaultLanguage() }
            .onChange(of: directory.defaultLanguage) { _, _ in applyOrgDefaultLanguage() }
    }

    @ViewBuilder
    private var sheetContent: some View {
        #if os(iOS)
            NavigationStack {
                ScrollView {
                    formContent
                        .padding()
                }
                .navigationTitle("New Question")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { sheetToolbar }
            }
            // iPad sizes to a resizable detent and shows a drag indicator so the form
            // reads as dismissible (#610).
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #else
            VStack(alignment: .leading, spacing: 16) {
                sheetHeader
                ScrollView {
                    formContent
                        .padding(.vertical, 2)
                }
                actionButtons
            }
            .padding()
            .frame(minWidth: 720, minHeight: 620)
        #endif
    }

    @ViewBuilder
    private var formContent: some View {
        #if os(macOS)
            HStack(alignment: .top, spacing: 16) {
                setupColumn
                    .frame(width: 280, alignment: .topLeading)
                editorColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        #else
            VStack(alignment: .leading, spacing: 16) {
                setupColumn
                editorColumn
            }
        #endif
    }

    private var sheetHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "questionmark.bubble")
                .font(.title3)
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            Text("New Question")
                .font(.title3.bold())
            Spacer()
        }
    }

    private var setupColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            titlePanel
            metadataPanel
            if QuestionDrafter.isAvailable {
                draftPanel
            }
            errorView
        }
    }

    private var titlePanel: some View {
        authorPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label("Title", systemImage: "textformat")
                    .font(.headline)
                TextField("", text: $title, prompt: Text("Two Sum with Constraints"))
                    .font(.title3.weight(.semibold))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Question title")
            }
        }
    }

    private var metadataPanel: some View {
        authorPanel {
            VStack(alignment: .leading, spacing: 12) {
                metadataPicker(title: "Language", systemImage: "curlybraces") {
                    Picker("Language", selection: languageSelection) {
                        ForEach(CoderPadLanguages.pickerOptions, id: \.self) {
                            Text($0.coderPadLanguageDisplayName).tag($0)
                        }
                        if !CoderPadLanguages.pickerOptions.contains(language) {
                            Text(language.coderPadLanguageDisplayName).tag(language)
                        }
                    }
                    .labelsHidden()
                }
                metadataPicker(title: "Type", systemImage: "rectangle.stack") {
                    Picker("Type", selection: $padType) {
                        ForEach(padTypeOptions, id: \.self) { Text(padTypeLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                }
            }
        }
    }

    private var draftPanel: some View {
        authorPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Draft", systemImage: "sparkles")
                    .font(.headline)
                TextField("", text: $draftPrompt,
                          prompt: Text("Reverse a linked list in place"),
                          axis: .vertical)
                    .lineLimit(3 ... 6)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Question prompt")
                Button(action: draftQuestion) {
                    if isDrafting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Drafting…")
                        }
                    } else {
                        Label("Draft Question", systemImage: "sparkles")
                    }
                }
                .disabled(isSubmitting
                    || isDrafting
                    || draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Draft the title, brief, candidate prompt, and solution")
            }
        }
    }

    @ViewBuilder
    private var errorView: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }

    private var editorColumn: some View {
        authorPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Label(selectedSection.editorTitle, systemImage: selectedSection.systemImage)
                        .font(.headline)
                    Spacer(minLength: 12)
                    Picker("Section", selection: $selectedSection) {
                        ForEach(QuestionDraftSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360)
                }

                DraftTextEditor(text: editorText,
                                placeholder: selectedSection.placeholder,
                                accessibilityLabel: selectedSection.accessibilityLabel,
                                isCode: selectedSection == .solution)
                    .frame(minHeight: 300)

                sectionStrip
            }
        }
    }

    private var sectionStrip: some View {
        HStack(spacing: 8) {
            ForEach(QuestionDraftSection.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.title, systemImage: section.systemImage)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedSection == section)
            }
            Spacer(minLength: 0)
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isSubmitting)
            createButton
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel, action: onCancel)
                .disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
            createButton
        }
    }

    private var createButton: some View {
        Button { Task { await submit() } } label: {
            if isSubmitting { ProgressView().controlSize(.small) } else { Text("Create") }
        }
        .keyboardShortcut(.defaultAction)
        #if os(macOS)
            .buttonStyle(.borderedProminent)
        #endif
            .disabled(isSubmitting || isDrafting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private extension NewQuestionSheet {
    func metadataPicker(title: LocalizedStringKey,
                        systemImage: String,
                        @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func authorPanel(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            }
    }

    /// The language picker's binding, marking the choice as user-made so the org
    /// default no longer overrides it.
    var languageSelection: Binding<String> {
        Binding(get: { language }, set: { language = $0; languageEdited = true })
    }

    var editorText: Binding<String> {
        Binding(get: { text(for: selectedSection) },
                set: { setText($0, for: selectedSection) })
    }

    func text(for section: QuestionDraftSection) -> String {
        switch section {
        case .description: description
        case .instructions: instructions
        case .solution: solution
        }
    }

    func setText(_ value: String, for section: QuestionDraftSection) {
        switch section {
        case .description: description = value
        case .instructions: instructions = value
        case .solution: solution = value
        }
    }

    /// Pre-select the organization's default language, unless the user has already
    /// chosen one. Driven by `OrgDirectory`, which is loaded app-wide.
    func applyOrgDefaultLanguage() {
        guard !languageEdited, let def = directory.defaultLanguage, !def.isEmpty else { return }

        language = def
    }

    /// Drafts fields from the prompt/language snapshot, applying returned values
    /// only to fields the user has not edited while the model was running.
    func draftQuestion() {
        let requestPrompt = draftPrompt
        let requestLanguage = language
        let requestFields = [title, description, instructions, solution]

        isDrafting = true
        Task {
            let draft = await QuestionDrafter.draft(prompt: requestPrompt, language: requestLanguage)
            isDrafting = false
            guard let draft, draftPrompt == requestPrompt, language == requestLanguage else { return }

            if !draft.title.isEmpty, title == requestFields[0] { title = draft.title }
            if !draft.description.isEmpty, description == requestFields[1] { description = draft.description }
            if !draft.instructions.isEmpty, instructions == requestFields[2] {
                instructions = draft.instructions
                selectedSection = .instructions
            }
            if !draft.solution.isEmpty, solution == requestFields[3] { solution = draft.solution }
        }
    }

    func submit() async {
        guard !isDrafting else { return }

        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let body = Self.normalizedCreateBody(Self.CreateDraft(
            title: title,
            language: language,
            description: description,
            instructions: instructions,
            solution: solution,
            padType: padType
        ))
        do {
            let created = try await client.createQuestion(body)
            onCreated(created)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension NewQuestionSheet {
    struct CreateDraft {
        var title: String
        var language: String
        var description: String
        var instructions: String
        var solution: String
        var padType: String
    }

    static func normalizedCreateBody(_ draft: CreateDraft) -> QuestionCreate {
        let trimmedInstructions = trimmedOrNil(draft.instructions)
        return QuestionCreate(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            language: draft.language,
            description: trimmedOrNil(draft.description),
            solution: trimmedOrNil(draft.solution),
            takeHome: draft.padType == "take-home",
            padType: draft.padType,
            candidateInstructions: trimmedInstructions.map {
                [CandidateInstructionPayload(instructions: $0, defaultVisible: true)]
            }
        )
    }

    private static func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// The long-form question content (description, candidate instructions, solution)
// is edited in place in `QuestionDetailView` via `InlineEditableText`, so there's
// no separate edit sheet anymore (#335).
