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
    var propertiesRows: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            propertyRow("Language") {
                Picker("", selection: languageBinding) {
                    ForEach(CoderPadLanguages.pickerOptions, id: \.self) {
                        Text($0.coderPadLanguageDisplayName).tag($0)
                    }
                    // Keep the question's current language selectable even when it
                    // isn't one of the common picker options.
                    if !CoderPadLanguages.isPickerOption(draftLanguage) {
                        Text(draftLanguage.coderPadLanguageDisplayName).tag(draftLanguage)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            propertyRow("Type") {
                Picker("", selection: typeBinding) {
                    ForEach(InterviewType.allCases, id: \.rawValue) {
                        Text($0.label).tag($0.rawValue)
                    }
                    if InterviewType(rawValue: draftPadType) == nil {
                        Text(draftPadTypeFallbackLabel)
                            .tag(draftPadType)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            readOnlyPropertyRows
        }
        .disabled(isReadOnly)
    }

    private var draftPadTypeFallbackLabel: String {
        draftPadType.replacingOccurrences(of: "_", with: " ").capitalized
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
                .foregroundStyle(.primary)
        }
    }

    private func yesNo(_ value: Bool) -> LocalizedStringKey {
        value ? "Yes" : "No"
    }

    /// A labeled row pairing a property name with its inline control. Keeping the
    /// two-column alignment on compact phones makes pairs like "Shared / Yes" read
    /// as one key-value row instead of unrelated stacked labels.
    private func propertyRow(_ label: LocalizedStringKey,
                             @ViewBuilder control: () -> some View) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .visionDetailSecondaryLabel()
                .gridColumnAlignment(.leading)
            control()
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    QuestionInlineCommitQueue.enqueue(account: accountID, client: client,
                                                      questionID: question.id,
                                                      field: .language) {
                        await commitLanguage(newValue)
                    }
                })
    }

    private var typeBinding: Binding<String> {
        Binding(get: { draftPadType },
                set: { newValue in
                    draftPadType = newValue
                    QuestionInlineCommitQueue.enqueue(account: accountID, client: client,
                                                      questionID: question.id,
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
        // Trimmed: a whitespace-only rename would render blank labels (#1801).
        let newTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
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
        // Only a known interview type commits (#1808): the picker's fallback row
        // tags the question's own raw API value, and re-sending an unvalidated
        // string would PUT it alongside a derived take_home flag.
        guard let type = InterviewType(rawType: padType) else {
            draftPadType = currentType
            return
        }

        // `take_home` and `pad_type` are coupled, so a type change commits both.
        await save(QuestionUpdate(id: question.id, takeHome: type == .takeHome, padType: type.rawValue),
                   optimistic: { optimisticQuestion(padType: type.rawValue) },
                   revert: {
                       draftPadType = currentType
                   })
    }

    func replaceStarterFiles(_ files: [QuestionFileContent]) async throws {
        let context = AccountClientContext(client: client, targetAccountID: accountID)
        guard let current = context.resolve(in: accounts.accounts) else {
            throw AccountClientContextError.accountChanged
        }
        let updated = try await current.makeClient().updateQuestion(
            QuestionUpdate(id: question.id, fileContents: files)
        )
        guard context.resolve(in: accounts.accounts) != nil else {
            throw AccountClientContextError.accountChanged
        }
        latestQuestion = updated
        AppRouter.questionUpdated(updated, account: accountID)
    }

    func replaceProjectZIP(_ upload: QuestionZIPUpload) async throws {
        let context = AccountClientContext(client: client, targetAccountID: accountID)
        guard let current = context.resolve(in: accounts.accounts) else {
            throw AccountClientContextError.accountChanged
        }
        let updated = try await current.makeClient().updateQuestion(
            QuestionUpdate(id: question.id),
            zipFile: upload
        )
        guard context.resolve(in: accounts.accounts) != nil else {
            throw AccountClientContextError.accountChanged
        }
        latestQuestion = updated
        AppRouter.questionUpdated(updated, account: accountID)
    }
}
