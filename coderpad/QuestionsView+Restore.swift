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
    func persistSelectedQuestion(_ selectedQuestionID: Int?, account: UUID?) {
        guard didRestoreSelection, let account else { return }

        let key = Self.selectedQuestionKey(account)
        if let selectedQuestionID {
            UserDefaults.standard.set(selectedQuestionID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func topRowKey(_ account: UUID) -> String {
        "questions.topRow.\(account.uuidString)"
    }

    /// Persist the id of the row at the top of the list viewport, per account, so an
    /// *unselected* list reopens scrolled to roughly where it was left (#273) — the
    /// selection restore already covers the selected case. Guarded by the selection
    /// restore so the empty startup state can't clobber the saved id.
    func persistTopRow(_ id: Int?, account: UUID?) {
        guard didRestoreSelection, let account else { return }

        let key = Self.topRowKey(account)
        if let id {
            UserDefaults.standard.set(id, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func scheduleTopRowPersistence(_ id: Int?) {
        // Capture the owning account now: the write is debounced, and a fast account
        // switch would otherwise save this account's top row under the next
        // account's key (#757). The list epoch is captured for the same reason within
        // one account: a reload replaces the rows, and a callback queued against the
        // old ones must not overwrite a scroll position taken since (#2503).
        let account = accounts.currentAccountID
        let epoch = questionsRevision
        topRowPersistence.schedule {
            guard epoch == questionsRevision else { return }

            persistTopRow(id, account: account)
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
    /// `loadComplete` is true only once the incremental load has finished. Until then
    /// a saved id that isn't in the list yet may simply be on a page still arriving, so
    /// the one-shot restore waits rather than being spent on a partial list (#2501).
    func restoreSelectedQuestionIfNeeded(loadComplete: Bool = false) {
        guard !didRestoreSelection, !questions.isEmpty else { return }
        guard let account = accounts.currentAccountID else { return }

        let availableIDs = Set(questions.map(\.id))
        let stored = UserDefaults.standard.object(forKey: Self.selectedQuestionKey(account)) as? Int
        let storedTop = UserDefaults.standard.object(forKey: Self.topRowKey(account)) as? Int
        if !loadComplete,
           [stored, storedTop].contains(where: { $0.map { !availableIDs.contains($0) } ?? false }) {
            return
        }

        didRestoreSelection = true
        // The load has finished and these ids aren't in it, so the questions are gone.
        // Clear them rather than rechecking the same dead ids on every launch (#2502).
        if let stored, !availableIDs.contains(stored) {
            UserDefaults.standard.removeObject(forKey: Self.selectedQuestionKey(account))
        }
        if let storedTop, !availableIDs.contains(storedTop) {
            UserDefaults.standard.removeObject(forKey: Self.topRowKey(account))
        }
        if let id = Self.questionToRestore(
            savedID: stored,
            hasSelection: selection != nil,
            hasPendingNavigation: pendingSelectQuestionID != nil || nav.questionsRequest != nil,
            availableIDs: availableIDs
        ) {
            selectedQuestionIDs = [id]
            // Bring the restored row into view; the List won't scroll to it on its own.
            pendingScrollToID = id
        } else if selection == nil, pendingSelectQuestionID == nil, nav.questionsRequest == nil,
                  let topID = storedTop, availableIDs.contains(topID) {
            // Nothing to reselect — return the unselected list to where it was scrolled
            // last session (#273), without selecting anything.
            pendingScrollToID = topID
        }
    }
}
