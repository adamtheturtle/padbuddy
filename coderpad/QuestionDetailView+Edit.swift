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

private enum QuestionInlineCommitField: String {
    case language
    case type
}

@MainActor
private enum QuestionInlineCommitQueue {
    private static var running: [String: Task<Void, Never>] = [:]
    private static var pending: [String: @MainActor () async -> Void] = [:]

    /// Serializes saves per account + question + field. The key carries the owning
    /// account: per-org question ids collide across accounts, so a process-global
    /// numeric key made unrelated accounts' saves wait on each other and retained
    /// the other window's state (#1183). While a save is in flight only the newest
    /// queued value is kept, so rapid Picker churn sends at most one trailing PUT
    /// with the final choice instead of replaying every intermediate value (#1185).
    /// Entries are removed as their work drains, so completed tasks and their
    /// captured views aren't retained for the life of the process (#1184).
    static func enqueue(account: UUID?,
                        questionID: Int,
                        field: QuestionInlineCommitField,
                        operation: @escaping @MainActor () async -> Void) {
        let key = "\(account?.uuidString ?? "current"):\(questionID):\(field.rawValue)"
        guard running[key] == nil else {
            pending[key] = operation
            return
        }

        run(key: key, operation: operation)
    }

    private static func run(key: String, operation: @escaping @MainActor () async -> Void) {
        running[key] = Task { @MainActor in
            await operation()
            running[key] = nil
            if let next = pending.removeValue(forKey: key) {
                run(key: key, operation: next)
            }
        }
    }
}

/// Serializes whole-array candidate-instruction saves per account + question:
/// each save resends the entire instruction list, so two concurrent part edits
/// would each PUT an array holding the other part's old text and the later one
/// would win (#1188). Chaining them (and building each payload from the latest
/// published question inside the chained block) makes the second save see the
/// first one's result. Entries are removed when a chain drains.
@MainActor
private enum QuestionInstructionSaveChain {
    private static var tails: [String: Task<Void, Never>] = [:]

    static func run(key: String, operation: @escaping @MainActor () async -> Bool) async -> Bool {
        let previous = tails[key]
        let task = Task { @MainActor () -> Bool in
            await previous?.value
            return await operation()
        }
        let tail = Task { @MainActor in _ = await task.value }
        tails[key] = tail
        let result = await task.value
        if tails[key] == tail { tails[key] = nil }
        return result
    }
}

extension QuestionDetailView {
    /// The editable metadata, presented as labeled rows of inline controls. Title is
    /// edited in the header; language and type live here.
    var propertiesCard: some View {
        DetailSection(title: "Properties", systemImage: "slider.horizontal.3") {
            propertiesRows
        }
        // Offline → read-only: disable the inline metadata editors so a field change
        // can't fire a doomed PUT against an unreachable server (#321).
        .disabled(isReadOnly)
    }

    var propertiesRows: some View {
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
            readOnlyPropertyRows
        }
        .disabled(isReadOnly)
    }

    @ViewBuilder
    private var readOnlyPropertyRows: some View {
        if let shared = question.shared {
            readOnlyPropertyRow("Shared", value: yesNo(shared))
        }
        if let enabled = question.testCasesEnabled {
            readOnlyPropertyRow("Test cases", value: enabled ? "Enabled" : "Disabled")
        }
        if let draft = question.isDraft {
            readOnlyPropertyRow("Draft", value: yesNo(draft))
        }
        readOnlyPropertyRow(
            "Public link",
            value: question.publicTakeHomeSettingID == nil ? "Not configured" : "Configured"
        )
    }

    private func readOnlyPropertyRow(_ label: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        propertyRow(label) {
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func yesNo(_ value: Bool) -> LocalizedStringKey {
        value ? "Yes" : "No"
    }

    /// A labeled row pairing a property name with its inline control, matching the
    /// alignment of the read-only rows elsewhere in the detail view. Compact phones
    /// stack the control below the label so pickers are not squeezed beside it.
    @ViewBuilder
    private func propertyRow(_ label: LocalizedStringKey,
                             @ViewBuilder control: () -> some View) -> some View {
        if isCompactPhone {
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                control()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 110, alignment: .leading)
                control()
                Spacer(minLength: 0)
            }
        }
    }

    private func scheduleSeedDrafts() {
        // Claim the newest generation: the displayed question can change again
        // before the queued block runs, and a stale callback would seed the
        // language/type drafts from the wrong question (#1192).
        draftSeedGeneration &+= 1
        let generation = draftSeedGeneration
        DispatchQueue.main.async {
            guard generation == draftSeedGeneration else { return }

            seedDrafts()
        }
    }

    /// Seeds the metadata drafts on appear and keeps each in sync with server-side
    /// changes (this view's own saves, or a push update). The title is no longer among
    /// these: `InlineEditableTitle` is now self-owning (it holds its own draft and focus
    /// and commits on Return / focus-loss), so it reads `question.title` directly.
    func draftSync(_ content: some View) -> some View {
        content
            .onChange(of: question.id, initial: true) { _, _ in
                latestQuestion = question
                scheduleSeedDrafts()
            }
            // Track every question change (a refresh, another window's edit bounced
            // back through the router) so optimistic saves merge into the freshest
            // base instead of republishing stale fields they never sent (#1187).
            .onChange(of: question) { _, newValue in latestQuestion = newValue }
            .onChange(of: question.language) { _, newValue in draftLanguage = newValue ?? "python3" }
            .onChange(of: question.padType) { _, _ in draftPadType = currentType }
    }

    // MARK: - Bindings

    private var languageBinding: Binding<String> {
        Binding(get: { draftLanguage },
                set: { newValue in
                    draftLanguage = newValue
                    QuestionInlineCommitQueue.enqueue(account: accountID, questionID: question.id,
                                                      field: .language) {
                        await commitLanguage(newValue)
                    }
                })
    }

    private var typeBinding: Binding<String> {
        Binding(get: { draftPadType },
                set: { newValue in
                    draftPadType = newValue
                    QuestionInlineCommitQueue.enqueue(account: accountID, questionID: question.id,
                                                      field: .type) {
                        await commitType(newValue)
                    }
                })
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
    /// title control can leave edit mode. On failure the control keeps its draft open,
    /// so this uses `saveContent` to report success instead of the `revert`-based `save`.
    func commitTitle(_ newTitle: String) async -> Bool {
        guard newTitle != question.title else { return true }

        return await saveContent(QuestionUpdate(id: question.id, title: newTitle)) {
            optimisticQuestion(title: newTitle)
        }
    }

    func commitLanguage(_ language: String) async {
        await save(QuestionUpdate(id: question.id, language: language),
                   optimistic: { optimisticQuestion(language: language) },
                   revert: {
                       draftLanguage = question.language ?? "python3"
                   })
    }

    func commitType(_ padType: String) async {
        // `take_home` and `pad_type` are coupled, so a type change commits both.
        await save(QuestionUpdate(id: question.id, takeHome: padType == "take-home", padType: padType),
                   optimistic: { optimisticQuestion(padType: padType) },
                   revert: {
                       draftPadType = currentType
                   })
    }

    // MARK: - Long-form content commits

    // Description, solution, and each candidate-instruction part are edited inline
    // (see `InlineEditableText`). Each commit sends only its own field and reports
    // success back so the editor can close, or stay open on failure.

    func commitDescription(_ text: String) async -> Bool {
        guard text != (question.description ?? "") else { return true }

        return await saveContent(QuestionUpdate(id: question.id, description: text)) {
            optimisticQuestion(description: text)
        }
    }

    func commitSolution(_ text: String) async -> Bool {
        guard text != (question.solution ?? "") else { return true }

        return await saveContent(QuestionUpdate(id: question.id, solution: text)) {
            optimisticQuestion(solution: text)
        }
    }

    /// Commits one candidate-instruction part. The whole list is resent with only
    /// `index`'s text changed (each part keeps its `default_visible`), so editing
    /// part 2 onwards no longer collapses the parts into one (#334). An out-of-range
    /// index appends a new part, which is how the first part is added to a question
    /// that had none. Saves are serialized per question and each payload is built
    /// from the latest published question inside the serialized block, so parallel
    /// edits to two parts can't overwrite each other's text (#1188).
    func commitInstruction(at index: Int, text: String) async -> Bool {
        await QuestionInstructionSaveChain.run(
            key: "\(accountID?.uuidString ?? "current"):\(question.id)"
        ) {
            await performCommitInstruction(at: index, text: text)
        }
    }

    private func performCommitInstruction(at index: Int, text: String) async -> Bool {
        var payloads = (latestQuestion ?? question).candidateInstructions.map {
            CandidateInstructionPayload(instructions: $0.instructions, defaultVisible: $0.defaultVisible)
        }
        if payloads.indices.contains(index) {
            guard payloads[index].instructions != text else { return true }

            payloads[index].instructions = text
        } else {
            guard !text.isEmpty else { return true }

            payloads.append(CandidateInstructionPayload(instructions: text, defaultVisible: true))
        }
        return await saveContent(QuestionUpdate(id: question.id, candidateInstructions: payloads)) {
            optimisticQuestion(candidateInstructions: payloads)
        }
    }

    /// The question with the immediately-committed metadata drafts (language, type)
    /// applied, plus whichever long-form field this commit changed. As with the pad
    /// editor, building from the full saved-draft set keeps concurrent edits from
    /// clobbering each other; `title` is supplied only by `commitTitle` so an
    /// uncommitted title isn't pushed out early (#376).
    func optimisticQuestion(title: String? = nil, language: String? = nil, padType: String? = nil,
                            description: String? = nil, solution: String? = nil,
                            candidateInstructions: [CandidateInstructionPayload]? = nil) -> Question {
        let base = latestQuestion ?? question
        let optimisticPadType = padType ?? draftPadType
        return base.applying(
            title: title, language: language ?? draftLanguage,
            takeHome: optimisticPadType == "take-home", padType: optimisticPadType,
            description: description, solution: solution,
            candidateInstructions: candidateInstructions
        )
    }

    /// Sends a single-field content update and propagates the optimistic question
    /// without the redundant re-GET (#376), returning whether it succeeded. On failure
    /// it surfaces the error; the inline editor keeps the unsaved text so nothing is lost.
    private func saveContent(_ body: QuestionUpdate, optimistic: () -> Question) async -> Bool {
        do {
            try await client.updateQuestionWithoutRefetch(body)
            let optimistic = optimistic()
            latestQuestion = optimistic
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
    private func save(_ body: QuestionUpdate, optimistic: () -> Question, revert: () -> Void) async {
        do {
            try await client.updateQuestionWithoutRefetch(body)
            let optimistic = optimistic()
            latestQuestion = optimistic
            AppRouter.questionUpdated(optimistic, account: accountID)
        } catch {
            editError = error.localizedDescription
            revert()
        }
    }
}
