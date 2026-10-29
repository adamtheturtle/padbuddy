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
    /// Publish the question -> owning-accounts map. Every owner is kept per id so
    /// bare-id lookups can refuse an ambiguous per-org collision instead of
    /// routing to whichever account happened to publish last (#1219).
    func publishRoutes() {
        guard RetainedListStream.areComplete(questionsByAccount.values.lazy.map(\.count)) else {
            router.setQuestionRoutes([:])
            return
        }

        var routes: [Int: Set<UUID>] = [:]
        for account in accounts.mergeableAccounts {
            for question in questionsByAccount[account.id] ?? [] {
                routes[question.id, default: []].insert(account.id)
            }
        }
        router.setQuestionRoutes(routes)
    }

    /// Apply an edited question to its account's list. `account` is the owning
    /// account from the notification; it disambiguates a per-org id collision.
    /// When absent, fall back to the routing map — which resolves only an
    /// unambiguous id, so a collision can't apply the edit to the wrong account's
    /// row (#1219).
    func applyUpdated(_ question: Question, account: UUID? = nil) {
        guard let accountID = account ?? router.uniqueAccountID(forQuestionID: question.id),
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
    /// is dropped, so a colliding id in another account is left intact. A bare-id
    /// event resolves against the loaded rows and is honored only when exactly one
    /// account holds the id: per-org ids collide routinely, and an accountless
    /// legacy deletion for id 42 must not remove unrelated question 42 rows from
    /// every merged account (#1220).
    func removeQuestion(id: Int, account: UUID? = nil) {
        let owner = account ?? {
            let holders = questionsByAccount.filter { $0.value.contains { $0.id == id } }.map(\.key)
            return holders.count == 1 ? holders.first : nil
        }()
        guard let owner else { return }

        questionsByAccount[owner] = questionsByAccount[owner]?.filter { $0.id != id }
        questionsRevision += 1
        publishRoutes()
    }

    /// Insert a just-created question at the top of its account's rows. A no-op
    /// when the account already holds the id, so a repeated create notification
    /// can't produce duplicate rows sharing one namespaced identity (#1221).
    func insert(_ question: Question, into account: Account) {
        var questions = questionsByAccount[account.id] ?? []
        guard !questions.contains(where: { $0.id == question.id }) else { return }

        questions.insert(question, at: 0)
        questionsByAccount[account.id] = questions
        questionsRevision += 1
        cache.set(account.id, questions: questions, via: account.makeClient())
        publishRoutes()
    }
}
