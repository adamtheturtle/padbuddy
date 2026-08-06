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
            starterFiles: starterFiles
        )
    }

    func restoreCreationDraft() {
        guard let account = draftAccountID,
              let draft = CreationDraftStore.load(QuestionCreationDraft.self, kind: "question", account: account)
        else { return }

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

    func persistCreationDraft(_ draft: QuestionCreationDraft) {
        guard let account = draftAccountID else { return }

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
