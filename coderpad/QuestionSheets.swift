//
//  QuestionSheets.swift
//  coderpad
//

import SwiftUI

// MARK: - Question Create / Edit sheets

private let padTypeOptions = InterviewType.allCases.map(\.rawValue)
private func padTypeLabel(_ raw: String) -> String {
    InterviewType(rawValue: raw)?.label ?? raw.capitalized
}

private enum QuestionDraftSection: String, CaseIterable, Identifiable {
    case description
    case instructions
    case solution

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .description: "Brief"
        case .instructions: "Candidate"
        case .solution: "Solution"
        }
    }

    var systemImage: String {
        switch self {
        case .description: "text.alignleft"
        case .instructions: "person.text.rectangle"
        case .solution: "chevron.left.forwardslash.chevron.right"
        }
    }

    var placeholder: LocalizedStringKey {
        switch self {
        case .description: "Summarize the problem an interviewer should understand before opening a pad."
        case .instructions: "Write the prompt candidates will see, including inputs, outputs, constraints, and examples."
        case .solution: "Add the reference solution or key implementation notes."
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .description: "Question brief"
        case .instructions: "Candidate instructions"
        case .solution: "Reference solution"
        }
    }
}

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
                .disabled(isDrafting || draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                    Label("Question Body", systemImage: selectedSection.systemImage)
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

    private func metadataPicker<Content: View>(title: LocalizedStringKey,
                                               systemImage: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(title, systemImage: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func authorPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
            }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: onCancel)
            createButton
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel, action: onCancel)
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
        .disabled(isSubmitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// The language picker's binding, marking the choice as user-made so the org
    /// default no longer overrides it.
    private var languageSelection: Binding<String> {
        Binding(get: { language }, set: { language = $0; languageEdited = true })
    }

    private var editorText: Binding<String> {
        Binding(get: { text(for: selectedSection) },
                set: { setText($0, for: selectedSection) })
    }

    private func text(for section: QuestionDraftSection) -> String {
        switch section {
        case .description: description
        case .instructions: instructions
        case .solution: solution
        }
    }

    private func setText(_ value: String, for section: QuestionDraftSection) {
        switch section {
        case .description: description = value
        case .instructions: instructions = value
        case .solution: solution = value
        }
    }

    /// Pre-select the organization's default language, unless the user has already
    /// chosen one. Driven by `OrgDirectory`, which is loaded app-wide.
    private func applyOrgDefaultLanguage() {
        guard !languageEdited, let def = directory.defaultLanguage, !def.isEmpty else { return }

        language = def
    }

    /// Drafts the question fields from the prompt, in the currently-selected
    /// language. Fills only the fields the model returned, so a partial draft
    /// doesn't blank anything the user already typed.
    private func draftQuestion() {
        isDrafting = true
        Task {
            let draft = await QuestionDrafter.draft(prompt: draftPrompt, language: language)
            isDrafting = false
            guard let draft else { return }

            if !draft.title.isEmpty { title = draft.title }
            if !draft.description.isEmpty { description = draft.description }
            if !draft.instructions.isEmpty {
                instructions = draft.instructions
                selectedSection = .instructions
            }
            if !draft.solution.isEmpty { solution = draft.solution }
        }
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
            let created = try await client.createQuestion(body)
            onCreated(created)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct DraftTextEditor: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    let accessibilityLabel: String
    var isCode = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(isCode ? .system(.body, design: .monospaced) : .body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .accessibilityLabel(accessibilityLabel)

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }
}

// The long-form question content (description, candidate instructions, solution)
// is edited in place in `QuestionDetailView` via `InlineEditableText`, so there's
// no separate edit sheet anymore (#335).
