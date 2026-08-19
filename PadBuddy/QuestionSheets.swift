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

    /// The members below are internal rather than private because the drafting,
    /// normalization, and submit logic lives in QuestionSheets+Drafting.swift, split
    /// out to keep both files under the file-length limit.
    @Environment(\.orgDirectory) var directory
    @State var accounts = AccountsStore.shared
    @State var title = ""
    @State var language = "python3"
    /// Set once the language is chosen deliberately — by the user in the picker, or
    /// by a draft/restoration path — so a late-arriving org default doesn't overwrite
    /// it (#2341).
    @State var languageEdited = false
    @State var description = ""
    @State var instructions = ""
    @State var solution = ""
    @State var starterFiles: [QuestionStarterFileDraft] = []
    @State var selectedProjectZIP: QuestionZIPSelection?
    @State var selectedSection: QuestionDraftSection = .instructions
    @State var padType = QuestionPadType.fallback
    @State var isSubmitting = false
    @State var error: String?
    @State var draftPrompt = ""
    @State var isDrafting = false
    /// Held so dismissing the sheet cancels the model work. It used to be an untracked
    /// Task that kept generating after the sheet was gone, then wrote into state
    /// nobody was showing (#2332).
    @State var draftTask: Task<Void, Never>?

    var body: some View {
        sheetContent
            .interactiveDismissDisabled(isSubmitting)
            .task { restoreCreationDraft() }
            .task { applyOrgDefaultLanguage() }
            .onChange(of: persistedCreationDraft) { _, draft in persistCreationDraft(draft) }
            .onChange(of: directory.defaultLanguage) { _, _ in applyOrgDefaultLanguage() }
            .onDisappear {
                draftTask?.cancel()
                draftTask = nil
            }
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
                TextField("", text: titleBinding, prompt: Text("Two Sum with Constraints"))
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
                    Picker("Type", selection: padTypeSelection) {
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
                DraftTextEditor(text: draftPromptBinding,
                                placeholder: "Reverse a linked list in place",
                                accessibilityLabel: "Question prompt")
                    .frame(minHeight: 96)
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
        VStack(alignment: .leading, spacing: 12) {
            authorPanel {
                VStack(alignment: .leading, spacing: 12) {
                    Label(selectedSection.editorTitle, systemImage: selectedSection.systemImage)
                        .font(.headline)
                        .lineLimit(1)

                    Picker("Section", selection: $selectedSection) {
                        ForEach(QuestionDraftSection.allCases) { section in
                            Text(section.title).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)

                    DraftTextEditor(text: editorText,
                                    placeholder: selectedSection.placeholder,
                                    accessibilityLabel: selectedSection.accessibilityLabel,
                                    isCode: selectedSection == .solution)
                        .frame(minHeight: 300)
                }
            }
            if language.lowercased().hasPrefix("multifile_") {
                authorPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        QuestionZIPPicker(selection: $selectedProjectZIP) { starterFiles.removeAll() }
                        if selectedProjectZIP == nil {
                            QuestionStarterFilesEditor(files: $starterFiles)
                        } else {
                            Button("Use Individual Starter Files") { selectedProjectZIP = nil }
                        }
                    }
                }
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel, action: cancelDraft)
                .disabled(isSubmitting)
            createButton
        }
    }

    @ToolbarContentBuilder
    private var sheetToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel, action: cancelDraft)
                .disabled(isSubmitting)
        }
        ToolbarItem(placement: .confirmationAction) {
            createButton
        }
    }

    private var createButton: some View {
        Button { Task { await submit() } } label: {
            if isSubmitting {
                ProgressView().controlSize(.small)
            } else {
                Text("Create")
            }
        }
        .keyboardShortcut(.defaultAction)
        #if os(macOS)
            .buttonStyle(.borderedProminent)
        #endif
            .disabled(isSubmitting || isDrafting
                || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || (selectedProjectZIP == nil && starterFiles.hasInvalidStarterFilePaths))
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
        var fileContents: [QuestionStarterFileDraft]

        init(
            title: String, language: String, description: String, instructions: String,
            solution: String, padType: String, fileContents: [QuestionStarterFileDraft] = []
        ) {
            self.title = title
            self.language = language
            self.description = description
            self.instructions = instructions
            self.solution = solution
            self.padType = padType
            self.fileContents = fileContents
        }
    }

    static func normalizedCreateBody(_ draft: CreateDraft) -> QuestionCreate {
        let trimmedInstructions = trimmedOrNil(draft.instructions)
        // Normalized once, so the two type fields are always derived from the same
        // value; an unrecognized `padType` used to be sent through verbatim while
        // `takeHome` fell to false, describing two different things (#2335).
        let padType = QuestionPadType.normalized(draft.padType)
        return QuestionCreate(
            title: String(draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(Limits.title)),
            language: draft.language,
            description: trimmedOrNil(draft.description),
            solution: trimmedOrNil(draft.solution),
            fileContents: draft.language.lowercased().hasPrefix("multifile_") && !draft.fileContents.isEmpty
                ? draft.fileContents.boundedForQuestionMutation.map(\.requestValue)
                : nil,
            takeHome: padType == InterviewType.takeHome.rawValue,
            padType: padType,
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
