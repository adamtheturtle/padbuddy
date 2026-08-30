//
//  QuestionDetailView+SaveIdentity.swift
//  coderpad
//

import Foundation

extension QuestionDetailView {
    func inlineEditTargetIsCurrent(
        questionID targetQuestionID: Int,
        accountID targetAccountID: UUID?,
        context: AccountClientContext
    ) -> Bool {
        guard question.id == targetQuestionID, accountID == targetAccountID else { return false }

        // Preview and test clients need not belong to a stored account. Their
        // immutable client value remains the complete identity boundary.
        guard context.accountID != nil else { return client.taskIdentity == context.clientIdentity }

        return context.resolve(in: accounts.accounts) != nil
    }
}
