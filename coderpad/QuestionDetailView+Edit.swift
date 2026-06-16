//
//  QuestionDetailView+Edit.swift
//  coderpad
//
//  Inline, save-per-field editing for a question's metadata (title, language,
//  type) and long-form content (description, candidate instructions, solution).
//  Each control commits its own `PUT /api/questions/:id` carrying only the field
//  that changed. The long-form fields are edited in place via `InlineEditableText`
//  rather than a separate window (#335).
//

import SwiftUI

extension QuestionDetailView {
    /// The editable metadata, presented as labeled rows of inline controls. Title is
    /// edited in the header; language and type live here.
    var propertiesCard: some View {
        DetailSection(title: "Properties", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                propertyRow("Language") {
                    Picker("", selection: languageBinding) {
                        ForEach(CoderPadLanguages.pickerOptions, id: \.self) {
                            Text($0.languageDisplayName).tag($0)
                        }
                        // Keep the question's current language selectable even when it
                        // isn't one of the common picker options.
                        if !CoderPadLanguages.pickerOptions.contains(draftLanguage) {
                            Text(draftLanguage.languageDisplayName).tag(draftLanguage)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                propertyRow("Type") {
                    Picker("", selection: typeBinding) {
                        ForEach(InterviewType.allCases, id: \.rawValue) {
                            Text($0.label).tag($0.rawValue)
                        }
                        if InterviewType(rawValue: draftPadType) == nil {
                            Text(draftPadType.capitalized).tag(draftPadType)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        // Offline → read-only: disable the inline metadata editors so a field change
        // can't fire a doomed PUT against an unreachable server (#321).
        .disabled(isReadOnly)
    }

    /// A labeled row pairing a property name with its inline control, matching the
    /// alignment of the read-only rows elsewhere in the detail view.
    @ViewBuilder
    private func propertyRow<Control: View>(_ label: LocalizedStringKey,
                                            @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }

    /// Seeds the metadata drafts on appear and keeps each in sync with server-side
    /// changes (this view's own saves, or a push update) — except the title while
    /// it's being typed. A title edit commits when focus leaves the field.
    func draftSync(_ content: some View) -> some View {
        content
            .onChange(of: question.id, initial: true) { _, _ in seedDrafts() }
            .onChange(of: question.title) { _, newValue in if !titleFocused { titleDraft = newValue } }
            .onChange(of: question.language) { _, newValue in draftLanguage = newValue ?? "python3" }
            .onChange(of: question.padType) { _, _ in draftPadType = currentType }
            .onChange(of: titleFocused) { _, focused in if !focused { Task { await commitTitle() } } }
    }

    // MARK: - Bindings

    private var languageBinding: Binding<String> {
        Binding(get: { draftLanguage },
                set: { newValue in draftLanguage = newValue; Task { await commitLanguage(newValue) } })
    }

    private var typeBinding: Binding<String> {
        Binding(get: { draftPadType },
                set: { newValue in draftPadType = newValue; Task { await commitType(newValue) } })
    }

    // MARK: - Drafts

    /// The question's current type as a `pad_type` raw value, derived from the
    /// `take_home` flag when the explicit `pad_type` is absent.
    var currentType: String {
        question.padType ?? (question.takeHome == true ? "take-home" : "live")
    }

    func seedDrafts() {
        titleDraft = question.title
        draftLanguage = question.language ?? "python3"
        draftPadType = currentType
    }

    // MARK: - Per-field commits

    func commitTitle() async {
        let newTitle = titleDraft
        guard newTitle != question.title else { return }
        await save(QuestionUpdate(id: question.id, title: newTitle)) { titleDraft = question.title }
    }

    func commitLanguage(_ language: String) async {
        guard language != question.language else { return }
        await save(QuestionUpdate(id: question.id, language: language)) {
            draftLanguage = question.language ?? "python3"
        }
    }

    func commitType(_ padType: String) async {
        guard padType != currentType else { return }
        // `take_home` and `pad_type` are coupled, so a type change commits both.
        await save(QuestionUpdate(id: question.id, takeHome: padType == "take-home", padType: padType)) {
            draftPadType = currentType
        }
    }

    // MARK: - Long-form content commits

    // Description, solution, and each candidate-instruction part are edited inline
    // (see `InlineEditableText`). Each commit sends only its own field and reports
    // success back so the editor can close, or stay open on failure.

    func commitDescription(_ text: String) async -> Bool {
        guard text != (question.description ?? "") else { return true }
        return await saveContent(QuestionUpdate(id: question.id, description: text))
    }

    func commitSolution(_ text: String) async -> Bool {
        guard text != (question.solution ?? "") else { return true }
        return await saveContent(QuestionUpdate(id: question.id, solution: text))
    }

    /// Commits one candidate-instruction part. The whole list is resent with only
    /// `index`'s text changed (each part keeps its `default_visible`), so editing
    /// part 2 onwards no longer collapses the parts into one (#334). An out-of-range
    /// index appends a new part, which is how the first part is added to a question
    /// that had none.
    func commitInstruction(at index: Int, text: String) async -> Bool {
        var payloads = question.candidateInstructions.map {
            CandidateInstructionPayload(instructions: $0.instructions, defaultVisible: $0.defaultVisible)
        }
        if payloads.indices.contains(index) {
            guard payloads[index].instructions != text else { return true }
            payloads[index].instructions = text
        } else {
            guard !text.isEmpty else { return true }
            payloads.append(CandidateInstructionPayload(instructions: text, defaultVisible: true))
        }
        return await saveContent(QuestionUpdate(id: question.id, candidateInstructions: payloads))
    }

    /// Sends a single-field content update and propagates the refreshed question,
    /// returning whether it succeeded. On failure it surfaces the error; the inline
    /// editor keeps the unsaved text so nothing is lost.
    private func saveContent(_ body: QuestionUpdate) async -> Bool {
        do {
            let saved = try await client.updateQuestion(body)
            AppRouter.questionUpdated(saved, account: accountID)
            return true
        } catch {
            editError = error.localizedDescription
            return false
        }
    }

    /// Sends a single-field update and propagates the refreshed question. On failure
    /// it surfaces the error and runs `revert` to snap the field back to the server's
    /// value, so the control never lies about what's saved.
    private func save(_ body: QuestionUpdate, revert: () -> Void) async {
        do {
            let saved = try await client.updateQuestion(body)
            AppRouter.questionUpdated(saved, account: accountID)
        } catch {
            editError = error.localizedDescription
            revert()
        }
    }
}
