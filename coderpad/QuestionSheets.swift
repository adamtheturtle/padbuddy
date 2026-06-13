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
                        .lineLimit(3 ... 8)
                }
                Section("Candidate instructions") {
                    TextField("", text: $instructions, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(4 ... 12)
                }
                Section("Solution") {
                    TextField("", text: $solution, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3 ... 12)
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
            let created = try await client.createQuestion(body)
            onCreated(created)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct EditQuestionSheet: View {
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
                    if !CoderPadLanguages.pickerOptions.contains(language) {
                        Text(language.languageDisplayName).tag(language)
                    }
                }
                Picker("Type", selection: $padType) {
                    ForEach(padTypeOptions, id: \.self) { Text(padTypeLabel($0)).tag($0) }
                    if !padTypeOptions.contains(padType) { Text(padType).tag(padType) }
                }
                Section("Description") {
                    TextField("", text: $description, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3 ... 8)
                }
                Section("Candidate instructions") {
                    TextField("", text: $instructions, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(4 ... 12)
                }
                Section("Solution") {
                    TextField("", text: $solution, prompt: Text("Optional"), axis: .vertical)
                        .lineLimit(3 ... 12)
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
                    defaultVisible: original.candidateInstructions.first?.defaultVisible ?? true
                )]
        )
        do {
            let saved = try await client.updateQuestion(body)
            onSaved(saved)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
