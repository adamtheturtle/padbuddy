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
    @State private var padType = "live"
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var draftPrompt = ""
    @State private var isDrafting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Question").font(.title3.bold())
            Form {
                // On-device authoring assist: describe a question and the model
                // drafts the fields below in the selected language. Shown only when
                // the model is available; every drafted field stays editable.
                if QuestionDrafter.isAvailable {
                    Section("Draft with AI") {
                        TextField("", text: $draftPrompt,
                                  prompt: Text("Describe a question, e.g. reverse a linked list"),
                                  axis: .vertical)
                            .lineLimit(2 ... 4)
                            .accessibilityLabel("Question prompt")
                        Button(action: draftQuestion) {
                            if isDrafting {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Drafting…")
                                }
                            } else {
                                Label("Draft fields", systemImage: "sparkles")
                            }
                        }
                        .disabled(isDrafting || draftPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Draft the title, description, instructions, and solution")
                    }
                }
                TextField("Title", text: $title)
                Picker("Language", selection: languageSelection) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) { Text($0.coderPadLanguageDisplayName).tag($0) }
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.coderPadLanguageDisplayName).tag(language)
                    }
                }
                Picker("Type", selection: $padType) {
                    ForEach(padTypeOptions, id: \.self) { Text(padTypeLabel($0)).tag($0) }
                }
                Section("Description") {
                    TextField("", text: $description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3 ... 8)
                        .accessibilityLabel("Description")
                }
                Section("Candidate instructions") {
                    TextField("", text: $instructions, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(4 ... 12)
                        .accessibilityLabel("Candidate instructions")
                }
                Section("Solution") {
                    TextField("", text: $solution, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3 ... 12)
                        .accessibilityLabel("Solution")
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
        // macOS sizes the sheet with a fixed frame; iPad sizes to a resizable detent and
        // shows a drag indicator so the form reads as dismissible (#610).
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 540)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
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
            if !draft.instructions.isEmpty { instructions = draft.instructions }
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

// The long-form question content (description, candidate instructions, solution)
// is edited in place in `QuestionDetailView` via `InlineEditableText`, so there's
// no separate edit sheet anymore (#335).
