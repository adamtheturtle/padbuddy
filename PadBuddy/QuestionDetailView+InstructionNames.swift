import Foundation

extension QuestionDetailView {
    func commitInstructionName(edit: InstructionNameEdit, name: String) async -> Bool {
        let context = AccountClientContext(client: client, targetAccountID: edit.accountID)
        return await serializedContentSave {
            guard client.taskIdentity == edit.clientIdentity,
                  inlineEditTargetIsCurrent(questionID: edit.questionID, accountID: edit.accountID, context: context),
                  !isReadOnly else { return false }
            guard let base = await questionForContentSave() else { return false }
            guard client.taskIdentity == edit.clientIdentity,
                  inlineEditTargetIsCurrent(questionID: edit.questionID, accountID: edit.accountID, context: context),
                  !isReadOnly
            else { return false }
            guard let payloads = QuestionInstructionNames.renamed(
                base.candidateInstructions, edit: edit, name: name
            ) else {
                editError = String(
                    localized: "Candidate instructions changed elsewhere. Review the latest parts, then save again."
                )
                publish(base)
                return false
            }

            return await saveContent(QuestionUpdate(id: question.id, candidateInstructions: payloads)) {
                optimisticQuestion(candidateInstructions: payloads)
            }
        }
    }
}
