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
                            Text($0.coderPadLanguageDisplayName).tag($0)
                        }
                        // Keep the question's current language selectable even when it
                        // isn't one of the common picker options.
                        if !CoderPadLanguages.pickerOptions.contains(draftLanguage) {
                            Text(draftLanguage.coderPadLanguageDisplayName).tag(draftLanguage)
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
                            Text(draftPadType.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(draftPadType)
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
    private func propertyRow(_ label: LocalizedStringKey,
                             @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
    }

    /// Seeds the metadata drafts on appear and keeps each in sync with server-side
    /// changes (this view's own saves, or a push update). The title is no longer among
    /// these: `InlineEditableTitle` is now self-owning (it holds its own draft and focus
    /// and commits on Return / focus-loss), so it reads `question.title` directly.
    func draftSync(_ content: some View) -> some View {
        content
            .onChange(of: question.id, initial: true) { _, _ in seedDrafts() }
            .onChange(of: question.language) { _, newValue in draftLanguage = newValue ?? "python3" }
            .onChange(of: question.padType) { _, _ in draftPadType = currentType }
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
    /// `take_home` flag when the explicit `pad_type` is absent. Normalizes the
    /// API's underscore spellings (e.g. `take_home`) to the canonical hyphenated
    /// `InterviewType` raw value so the picker matches a known option rather than
    /// falling through to the raw-string branch (#462).
    var currentType: String {
        if let normalized = InterviewType(rawType: question.padType) {
            return normalized.rawValue
        }
        if let padType = question.padType, !padType.isEmpty {
            return padType
        }
        return question.takeHome == true ? "take-home" : "live"
    }

    func seedDrafts() {
        draftLanguage = question.language ?? "python3"
        draftPadType = currentType
    }

    // MARK: - Per-field commits

    /// Commits an inline title rename, returning whether it saved so the self-owning
    /// `InlineEditableTitle` can leave edit mode. On failure the host keeps the old
    /// title (the control reverts by just leaving edit mode), so there's no draft to
    /// reset — hence the `saveContent` path (which reports success) rather than the
    /// `revert`-based `save`.
    func commitTitle(_ newTitle: String) async -> Bool {
        guard newTitle != question.title else { return true }

        return await saveContent(QuestionUpdate(id: question.id, title: newTitle),
                                 optimistic: optimisticQuestion(title: newTitle))
    }

    func commitLanguage(_ language: String) async {
        guard language != question.language else { return }

        await save(QuestionUpdate(id: question.id, language: language),
                   optimistic: optimisticQuestion()) {
            draftLanguage = question.language ?? "python3"
        }
    }

    func commitType(_ padType: String) async {
        guard padType != currentType else { return }

        // `take_home` and `pad_type` are coupled, so a type change commits both.
        await save(QuestionUpdate(id: question.id, takeHome: padType == "take-home", padType: padType),
                   optimistic: optimisticQuestion()) {
            draftPadType = currentType
        }
    }

    // MARK: - Long-form content commits

    // Description, solution, and each candidate-instruction part are edited inline
    // (see `InlineEditableText`). Each commit sends only its own field and reports
    // success back so the editor can close, or stay open on failure.

    func commitDescription(_ text: String) async -> Bool {
        guard text != (question.description ?? "") else { return true }

        return await saveContent(QuestionUpdate(id: question.id, description: text),
                                 optimistic: optimisticQuestion(description: text))
    }

    func commitSolution(_ text: String) async -> Bool {
        guard text != (question.solution ?? "") else { return true }

        return await saveContent(QuestionUpdate(id: question.id, solution: text),
                                 optimistic: optimisticQuestion(solution: text))
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
        return await saveContent(QuestionUpdate(id: question.id, candidateInstructions: payloads),
                                 optimistic: optimisticQuestion(candidateInstructions: payloads))
    }

    /// The question with the immediately-committed metadata drafts (language, type)
    /// applied, plus whichever long-form field this commit changed. As with the pad
    /// editor, building from the full saved-draft set keeps concurrent edits from
    /// clobbering each other; `title` is supplied only by `commitTitle` so an
    /// uncommitted title isn't pushed out early (#376).
    func optimisticQuestion(title: String? = nil, description: String? = nil, solution: String? = nil,
                            candidateInstructions: [CandidateInstructionPayload]? = nil) -> Question {
        question.applying(
            title: title, language: draftLanguage,
            takeHome: draftPadType == "take-home", padType: draftPadType,
            description: description, solution: solution,
            candidateInstructions: candidateInstructions
        )
    }

    /// Sends a single-field content update and propagates the optimistic question
    /// without the redundant re-GET (#376), returning whether it succeeded. On failure
    /// it surfaces the error; the inline editor keeps the unsaved text so nothing is lost.
    private func saveContent(_ body: QuestionUpdate, optimistic: Question) async -> Bool {
        do {
            try await client.updateQuestionWithoutRefetch(body)
            AppRouter.questionUpdated(optimistic, account: accountID)
            return true
        } catch {
            editError = error.localizedDescription
            return false
        }
    }

    /// Sends a single-field update and propagates the optimistic question without the
    /// redundant re-GET (#376). On failure it surfaces the error and runs `revert` to
    /// snap the field back to the server's value, so the control never lies about what's
    /// saved.
    private func save(_ body: QuestionUpdate, optimistic: Question, revert: () -> Void) async {
        do {
            try await client.updateQuestionWithoutRefetch(body)
            AppRouter.questionUpdated(optimistic, account: accountID)
        } catch {
            editError = error.localizedDescription
            revert()
        }
    }
}
