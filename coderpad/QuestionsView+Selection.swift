//
//  QuestionsView+Selection.swift
//  coderpad
//
//  Selecting a question by id, including the deferred case where the row hasn't
//  loaded yet. Split from QuestionsView.swift to keep that file under the
//  file-length limit.
//

import SwiftUI

extension QuestionsView {
    func selectQuestion(id: Int) {
        if containsQuestion(id) {
            selectedQuestionIDs = [id]
            // Reveal it: a favorite picked from the sidebar may sit far down the list.
            pendingScrollToID = id
            pendingSelectQuestionID = nil
        } else {
            pendingSelectQuestionID = id
        }
    }

    func resolvePendingSelection() {
        guard let id = pendingSelectQuestionID, containsQuestion(id) else { return }

        selectedQuestionIDs = [id]
        pendingScrollToID = id
        pendingSelectQuestionID = nil
    }

    /// Whether the loaded list holds this question, via an id index rebuilt only when
    /// the list itself changes.
    ///
    /// Both callers only needed to know *whether* the row is present — they used the
    /// matched value solely for its own id. `first(where:)` therefore scanned the whole
    /// list, and `resolvePendingSelection` repeats after every incremental page until
    /// the row turns up, so that scan ran once per page (#2477).
    private func containsQuestion(_ id: Int) -> Bool {
        if questionIDIndex.revision != questionsRevision {
            questionIDIndex = (questionsRevision, Set(questions.map(\.id)))
        }
        return questionIDIndex.ids.contains(id)
    }
}
