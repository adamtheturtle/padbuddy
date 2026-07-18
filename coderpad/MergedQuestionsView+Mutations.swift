//
//  MergedQuestionsView+Mutations.swift
//  coderpad
//
//  In-place row mutations (edit, delete, create) for the combined "All Accounts"
//  questions list, split from MergedQuestionsView+Logic.swift to keep it under
//  the length lint.
//

import SwiftUI

extension MergedQuestionsView {
    /// Apply an edited question to its account's list. `account` is the owning
    /// account from the notification; it disambiguates a per-org id collision. When
    /// absent, fall back to the (collision-prone) routing map as before.
    func applyUpdated(_ question: Question, account: UUID? = nil) {
        guard let accountID = account ?? router.questionAccountID[question.id],
              var questions = questionsByAccount[accountID],
              let index = questions.firstIndex(where: { $0.id == question.id }) else { return }

        questions[index] = question
        questionsByAccount[accountID] = questions
        questionsRevision += 1
        // Write the edit through to the cache (deletions already do), so a section
        // re-entry and Spotlight don't serve the stale pre-edit row (#1005).
        cache.updateQuestion(question, account: accountID)
        // Question ids collide across accounts, so also require the edited
        // question to belong to the account whose question is currently routed
        // into the detail pane — otherwise account B's edit would silently
        // replace account A's open question.
        if selection?.id == question.id, accountID == router.selectedQuestionAccountID {
            selection = question
        }
    }

    /// Remove a deleted question. With a known `account`, only that account's copy
    /// is dropped, so a colliding id in another account is left intact; without it,
    /// every account holding the id is updated (the prior behavior).
    func removeQuestion(id: Int, account: UUID? = nil) {
        let targets = account.map { [$0] } ?? Array(questionsByAccount.keys)
        for accountID in targets where questionsByAccount[accountID]?.contains(where: { $0.id == id }) == true {
            questionsByAccount[accountID] = questionsByAccount[accountID]?.filter { $0.id != id }
        }
        publishRoutes()
    }

    func insert(_ question: Question, into account: Account) {
        var questions = questionsByAccount[account.id] ?? []
        questions.insert(question, at: 0)
        questionsByAccount[account.id] = questions
        cache.set(account.id, questions: questions, via: account.makeClient())
        publishRoutes()
    }
}
