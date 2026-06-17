//
//  QuestionsView+Restore.swift
//  coderpad
//

import SwiftUI

extension QuestionsView {
    static func selectedQuestionKey(_ account: UUID) -> String {
        "questions.selectedQuestion.\(account.uuidString)"
    }

    /// Persist the id of the question shown in the detail pane, per account, so the
    /// list reopens to it next launch. Skipped until the restore has run so the empty
    /// startup state can't clobber the saved id; clearing the selection removes the
    /// stored id so a blank detail pane is restored faithfully too.
    func persistSelectedQuestion() {
        guard didRestoreSelection, let account = accounts.currentAccountID else { return }

        let key = Self.selectedQuestionKey(account)
        if let selectedQuestionID {
            UserDefaults.standard.set(selectedQuestionID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// The saved question to reselect on launch: the stored id, but only when nothing
    /// is already selected, no navigation is pending, and the id is still in the loaded
    /// list. Pure so the restore decision is unit-testable in isolation.
    static func questionToRestore(
        savedID: Int?,
        hasSelection: Bool,
        hasPendingNavigation: Bool,
        availableIDs: Set<Int>
    ) -> Int? {
        guard !hasSelection, !hasPendingNavigation,
              let savedID, availableIDs.contains(savedID) else { return nil }

        return savedID
    }

    /// Restore the previously-open question once its list is loaded. Marks the restore
    /// complete as soon as questions exist (so later changes persist), then reselects
    /// via `questionToRestore` — which yields to a pending favorite or queued request
    /// so an explicit navigation always wins.
    func restoreSelectedQuestionIfNeeded() {
        guard !didRestoreSelection, !questions.isEmpty else { return }

        didRestoreSelection = true
        guard let account = accounts.currentAccountID else { return }

        let stored = UserDefaults.standard.object(forKey: Self.selectedQuestionKey(account)) as? Int
        guard let id = Self.questionToRestore(
            savedID: stored,
            hasSelection: selection != nil,
            hasPendingNavigation: pendingSelectQuestionID != nil || nav.questionsRequest != nil,
            availableIDs: Set(questions.map(\.id))
        ) else { return }

        selectedQuestionIDs = [id]
        // Bring the restored row into view; the List won't scroll to it on its own.
        pendingScrollToID = id
    }
}
