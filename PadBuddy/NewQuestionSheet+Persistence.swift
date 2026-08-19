//
//  NewQuestionSheet+Persistence.swift
//  coderpad
//

import Foundation

extension NewQuestionSheet {
    var draftAccountID: UUID? {
        accounts.account(matching: client)?.id
    }

    var persistedCreationDraft: QuestionCreationDraft {
        QuestionCreationDraft(
            title: title, language: language, description: description,
            instructions: instructions, solution: solution, padType: padType,
            draftPrompt: draftPrompt, selectedSection: selectedSection.rawValue,
            starterFiles: starterFiles.boundedForQuestionMutation
        )
    }

    func restoreCreationDraft() {
        guard let account = draftAccountID else { return }
        guard case let .value(stored) = CreationDraftStore.load(
            QuestionCreationDraft.self, kind: "question", account: account
        ) else { return }

        let draft = Self.normalizedRestoredDraft(stored)

        title = draft.title
        language = draft.language
        languageEdited = true
        description = draft.description
        instructions = draft.instructions
        solution = draft.solution
        padType = QuestionPadType.normalized(draft.padType)
        draftPrompt = draft.draftPrompt
        selectedSection = QuestionDraftSection(rawValue: draft.selectedSection) ?? .instructions
        starterFiles = draft.starterFiles ?? []
    }

    static func normalizedRestoredDraft(_ draft: QuestionCreationDraft) -> QuestionCreationDraft {
        let language = CoderPadLanguages.pickerOptions.contains(draft.language) ? draft.language : "python3"
        let section = QuestionDraftSection(rawValue: draft.selectedSection) ?? .instructions
        let files = draft.starterFiles?.boundedForQuestionMutation
        return QuestionCreationDraft(
            title: String(draft.title.prefix(Limits.title)),
            language: language,
            description: String(draft.description.prefix(Limits.longForm)),
            instructions: String(draft.instructions.prefix(Limits.longForm)),
            solution: String(draft.solution.prefix(Limits.longForm)),
            padType: QuestionPadType.normalized(draft.padType),
            draftPrompt: String(draft.draftPrompt.prefix(Limits.draftPrompt)),
            selectedSection: section.rawValue,
            starterFiles: files
        )
    }

    func persistCreationDraft(_ draft: QuestionCreationDraft) {
        guard let account = draftAccountID else { return }

        var draft = draft
        draft.starterFiles = draft.starterFiles?.boundedForQuestionMutation

        if draft.isMeaningful {
            CreationDraftStore.save(draft, kind: "question", account: account)
        } else {
            CreationDraftStore.clear(kind: "question", account: account)
        }
    }

    func clearCreationDraft() {
        guard let account = draftAccountID else { return }

        CreationDraftStore.clear(kind: "question", account: account)
    }

    func cancelDraft() {
        clearCreationDraft()
        onCancel()
    }
}
