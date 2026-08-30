//
//  BulkDeleteActions+Questions.swift
//  coderpad
//
//  The question bulk-delete flows, split from BulkDeleteActions.swift to keep both
//  files under the file-length limit.
//

import SwiftUI

extension QuestionsView {
    func scheduleBulkDelete(_ questions: [Question]) {
        guard !questions.isEmpty else { return }

        questionsPendingBulkDelete = nil
        let items = BulkDeleteUndo.mergedItems(existing: pendingBulkDeleteUndo?.items ?? [], adding: questions)
        // Cancel only a grace timer still waiting to fire; see `PadsView`'s note.
        if pendingBulkDeleteUndo != nil {
            bulkDeleteUndoTask?.cancel()
        }
        let summary = BulkDeleteUndo.summary(of: items.map(\.displayTitle))
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting ^[\(items.count) questions](inflect: true): \(summary)")
        )
        pendingBulkDeleteUndo = pending
        // Doomed rows leave the list and selection for the grace period (#1262).
        selectedQuestionIDs.subtract(items.map(\.id))
        // Capture the owning account snapshot now: the task can fire after an
        // account switch, and per-org question ids collide across accounts, so
        // both the deletes and the broadcast must stay bound to the account that
        // scheduled them (#1013, #1209, like #757).
        let owningAccount = accounts.account(matching: client)
        bulkDeleteUndoTask = Task { @MainActor in
            do {
                try await BulkDeleteUndo.waitForGrace()
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Question bulk-delete grace timer failed: \(error)")
                return
            }
            guard pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            await bulkDelete(items, account: owningAccount)
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        // Undo restores the selection it took away, so the user can adjust it and try
        // again instead of re-picking every row (#2348).
        if let pending = pendingBulkDeleteUndo {
            selectedQuestionIDs.formUnion(pending.items.map(\.id))
        }
        pendingBulkDeleteUndo = nil
        bulkDeleteProgress = nil
    }

    @ViewBuilder
    var bulkDeleteUndoBanner: some View {
        if let pendingBulkDeleteUndo {
            BulkDeleteUndoBanner(message: pendingBulkDeleteUndo.message) { cancelBulkDelete() }
        } else if let bulkDeleteProgress {
            BulkDeleteProgressBanner(progress: bulkDeleteProgress) { cancelBulkDelete() }
        }
    }
}

extension MergedQuestionsView {
    func scheduleBulkDelete(_ rows: [MergedQuestionRow]) {
        guard !rows.isEmpty else { return }

        rowsPendingBulkDelete = nil
        let items = BulkDeleteUndo.mergedItems(existing: pendingBulkDeleteUndo?.items ?? [], adding: rows)
        // Cancel only a grace timer still waiting to fire; see `PadsView`'s note.
        if pendingBulkDeleteUndo != nil {
            bulkDeleteUndoTask?.cancel()
        }
        let summary = BulkDeleteUndo.summary(of: items.map(\.item.displayTitle))
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting ^[\(items.count) questions](inflect: true): \(summary)")
        )
        pendingBulkDeleteUndo = pending
        // Doomed rows leave the list and selection for the grace period (#1262).
        selectedRowIDs.subtract(items.map(\.id))
        bulkDeleteUndoTask = Task { @MainActor in
            do {
                try await BulkDeleteUndo.waitForGrace()
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Merged question bulk-delete grace timer failed: \(error)")
                return
            }
            guard pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            await bulkDelete(items)
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        // Undo restores the selection it took away (#2348).
        if let pending = pendingBulkDeleteUndo {
            selectedRowIDs.formUnion(pending.items.map(\.id))
        }
        pendingBulkDeleteUndo = nil
        bulkDeleteProgress = nil
    }

    @ViewBuilder
    var bulkDeleteUndoBanner: some View {
        if let pendingBulkDeleteUndo {
            BulkDeleteUndoBanner(message: pendingBulkDeleteUndo.message) { cancelBulkDelete() }
        } else if let bulkDeleteProgress {
            BulkDeleteProgressBanner(progress: bulkDeleteProgress) { cancelBulkDelete() }
        }
    }
}
