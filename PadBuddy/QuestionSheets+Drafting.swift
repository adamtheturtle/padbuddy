//
//  QuestionSheets+Drafting.swift
//  coderpad
//
//  The New Question sheet's drafting, normalization, and submit logic, split from
//  QuestionSheets.swift to keep both files under the file-length limit.
//

import SwiftUI

extension NewQuestionSheet {
    /// Caps on what the sheet will hold. The API rejects oversized payloads, and a
    /// multi-megabyte paste made the editor unusable long before the request was ever
    /// sent — so text is bounded where it enters, not only at submit (#2336).
    enum Limits {
        static let title = 200
        static let draftPrompt = 2000
        static let longForm = 100_000
        static let starterFilePath = 1000
    }

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

    /// The language picker's binding, marking the choice as deliberate so the org
    /// default no longer overrides it.
    var languageSelection: Binding<String> {
        Binding(get: { language }, set: {
            language = $0
            languageEdited = true
            if !Self.isProjectLanguage($0) {
                selectedProjectZIP = nil
            }
        })
    }

    static func isProjectLanguage(_ language: String) -> Bool {
        language.lowercased().hasPrefix("multifile_")
    }

    /// The title binding, bounded as it is typed or pasted (#2336).
    var titleBinding: Binding<String> {
        Binding(get: { title }, set: { title = String($0.prefix(Limits.title)) })
    }

    var draftPromptBinding: Binding<String> {
        Binding(get: { draftPrompt }, set: { draftPrompt = String($0.prefix(Limits.draftPrompt)) })
    }

    /// The type picker's binding, snapping anything unrecognized back to the default
    /// so the create body's `padType` and `takeHome` can never disagree (#2335).
    var padTypeSelection: Binding<String> {
        Binding(get: { QuestionPadType.normalized(padType) },
                set: { padType = QuestionPadType.normalized($0) })
    }

    var editorText: Binding<String> {
        Binding(get: { text(for: selectedSection) },
                set: { setText(String($0.prefix(Limits.longForm)), for: selectedSection) })
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

    /// Pre-select the organization's default language, unless one has already been
    /// chosen deliberately. Driven by `OrgDirectory`, which is loaded app-wide.
    func applyOrgDefaultLanguage() {
        // Only a language CoderPad actually offers. The directory value was applied
        // whatever it said and then added to the picker as its own option, so an
        // unrecognized code went through to question creation unchanged (#2334).
        guard !languageEdited,
              let def = directory.defaultLanguage,
              CoderPadLanguages.pickerOptions.contains(def) else { return }

        language = def
    }

    /// Model output, made safe to drop into an editor: control characters (other than
    /// the newlines and tabs long-form text legitimately contains) stripped, outer
    /// whitespace trimmed, and length bounded. It used to be copied verbatim and only
    /// trimmed much later, at submit (#2340).
    static func normalizedDraftText(_ raw: String, limit: Int) -> String {
        let cleaned = raw.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String(String.UnicodeScalarView(cleaned))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(limit))
    }

    /// Drafts fields from the prompt/language snapshot, applying returned values
    /// only to fields the user has not edited while the model was running.
    func draftQuestion() {
        let requestPrompt = draftPrompt
        let requestLanguage = language
        let requestFields = [title, description, instructions, solution]
        let requestSection = selectedSection

        error = nil; isDrafting = true
        draftTask?.cancel()
        draftTask = Task {
            let draft = await QuestionDrafter.draft(prompt: requestPrompt, language: requestLanguage)
            // Cancellation means the sheet went away, or a newer draft superseded this
            // one; either way nothing here should touch the sheet's state (#2332).
            guard !Task.isCancelled else { return }

            isDrafting = false
            guard draftPrompt == requestPrompt, language == requestLanguage else { return }
            guard let draft else {
                error = String(localized: "Draft failed. Try a more specific prompt, or draft again.")
                return
            }

            applyDraft(draft, over: requestFields, from: requestSection)
        }
    }

    private func applyDraft(_ draft: QuestionDrafter.Draft,
                            over requestFields: [String],
                            from requestSection: QuestionDraftSection) {
        let title = Self.normalizedDraftText(draft.title, limit: Limits.title)
        if !title.isEmpty, self.title == requestFields[0] {
            self.title = title
        }
        let description = Self.normalizedDraftText(draft.description, limit: Limits.longForm)
        if !description.isEmpty, self.description == requestFields[1] {
            self.description = description
        }
        let instructions = Self.normalizedDraftText(draft.instructions, limit: Limits.longForm)
        if !instructions.isEmpty, self.instructions == requestFields[2] {
            self.instructions = instructions
            // Only if the user is still where they were when the draft was requested.
            // Jumping them to Instructions after a background response yanked the
            // editor out from under someone mid-sentence in Brief or Solution (#2339).
            if selectedSection == requestSection {
                selectedSection = .instructions
            }
        }
        let solution = Self.normalizedDraftText(draft.solution, limit: Limits.longForm)
        if !solution.isEmpty, self.solution == requestFields[3] {
            self.solution = solution
        }
    }

    func submit() async {
        guard !isDrafting else { return }

        // Claim submission synchronously before any await so queued Return/tap
        // events cannot launch a second createQuestion (#4676).
        guard !isSubmitting else { return }

        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        let owningAccount = accounts.account(matching: client)
        let context = AccountClientContext(client: client, targetAccountID: owningAccount?.id)
        let body = Self.normalizedCreateBody(Self.CreateDraft(
            title: title,
            language: language,
            description: description,
            instructions: instructions,
            solution: solution,
            padType: padType,
            fileContents: starterFiles
        ))
        do {
            guard let current = context.resolve(in: accounts.accounts) else {
                throw AccountClientContextError.accountChanged
            }

            let currentClient = current.makeClient()
            let created = if Self.isProjectLanguage(language), let selectedProjectZIP {
                try await currentClient.createQuestion(body, zipFile: selectedProjectZIP.upload)
            } else {
                try await currentClient.createQuestion(body)
            }
            guard context.resolve(in: accounts.accounts) != nil else {
                throw AccountClientContextError.accountChanged
            }

            await APIReadCoordinator.shared.invalidateQuestions(accountID: current.id)
            clearCreationDraft()
            onCreated(created)
        } catch is CancellationError {
            // The sheet was dismissed or the account changed out from under the
            // request. That is not a failure the user needs to see (#2337).
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}
