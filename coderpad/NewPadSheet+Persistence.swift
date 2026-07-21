//
//  NewPadSheet+Persistence.swift
//  coderpad
//

import Foundation

extension NewPadSheet {
    var draftAccountID: UUID? {
        targetAccountID ?? AccountsStore.shared.account(matching: client)?.id
    }

    var persistedCreationDraft: PadCreationDraft {
        PadCreationDraft(
            title: title, language: language, ownerEmail: ownerEmail,
            isPrivate: isPrivate, executionEnabled: executionEnabled,
            questionID: selectedQuestionID, teamID: selectedTeamID
        )
    }

    func restoreCreationDraft() {
        guard let account = draftAccountID,
              let draft = CreationDraftStore.load(PadCreationDraft.self, kind: "pad", account: account) else { return }

        title = draft.title
        titleEdited = !draft.title.isEmpty
        language = draft.language
        languageEdited = true
        ownerEmail = draft.ownerEmail
        isPrivate = draft.isPrivate
        executionEnabled = draft.executionEnabled
        if initialQuestionID == nil { selectedQuestionID = draft.questionID }
        selectedTeamID = draft.teamID
    }

    func persistCreationDraft(_ draft: PadCreationDraft) {
        guard let account = draftAccountID else { return }

        if draft.isMeaningful {
            CreationDraftStore.save(draft, kind: "pad", account: account)
        } else {
            CreationDraftStore.clear(kind: "pad", account: account)
        }
    }

    func clearCreationDraft() {
        guard let account = draftAccountID else { return }

        CreationDraftStore.clear(kind: "pad", account: account)
    }

    func cancelDraft() {
        clearCreationDraft()
        onCancel()
    }
}
