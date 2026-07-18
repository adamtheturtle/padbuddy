//
//  Accounts+Cache+QuestionMutations.swift
//  coderpad
//
//  Single-question write-backs for QuestionsCacheStore, so an edit or a create is
//  reflected on every cache-backed surface (disk snapshot, Spotlight, the New Pad
//  from Question menu, a section re-entry) without waiting for the next full list
//  reload (#1005, #1007). Deletions already had this via `removeQuestion`; these are
//  the missing edit/insert counterparts, built on `get`/`set` so the full `set` side
//  effects run. Split from Accounts+Cache.swift to keep that file focused.
//

import Foundation

extension QuestionsCacheStore {
    /// Replaces one question in the account's cached list and re-runs the `set` side
    /// effects. A no-op when the account is unknown, the cached list doesn't contain
    /// the question, or the cached row is already identical (so repeated broadcasts
    /// don't churn Spotlight/disk).
    func updateQuestion(_ question: Question, account: UUID?) {
        // These write-backs happen under the account's current credentials, so the
        // stored account's own client is the identity token `set` validates (#754);
        // a vanished account simply no-ops.
        guard let account,
              let stored = AccountsStore.shared.accounts.first(where: { $0.id == account }) else { return }

        var questions = get(account)
        guard let index = questions.firstIndex(where: { $0.id == question.id }),
              questions[index] != question else { return }

        questions[index] = question
        set(account, questions: questions, via: stored.makeClient())
    }

    /// Inserts a newly created question at the head of the account's cached list
    /// (mirroring `MergedQuestionsView.insert`), so the create is visible beyond the
    /// list that made it.
    func insertQuestion(_ question: Question, account: UUID?) {
        guard let account,
              let stored = AccountsStore.shared.accounts.first(where: { $0.id == account }) else { return }

        var questions = get(account)
        questions.removeAll { $0.id == question.id }
        questions.insert(question, at: 0)
        set(account, questions: questions, via: stored.makeClient())
    }
}
