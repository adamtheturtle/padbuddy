//
//  BulkDeleteActions.swift
//  coderpad
//

import SwiftUI

extension PadsView {
    func scheduleBulkDelete(_ pads: [Pad]) {
        guard !pads.isEmpty else { return }

        padsPendingBulkDelete = nil
        let items = BulkDeleteUndo.mergedItems(existing: pendingBulkDeleteUndo?.items ?? [], adding: pads)
        bulkDeleteUndoTask?.cancel()
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting \(items.count) pads...")
        )
        pendingBulkDeleteUndo = pending
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil

            for pad in items {
                await deletePad(pad)
            }
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        pendingBulkDeleteUndo = nil
    }

    @ViewBuilder
    var bulkDeleteUndoBanner: some View {
        if let pendingBulkDeleteUndo {
            BulkDeleteUndoBanner(message: pendingBulkDeleteUndo.message) { cancelBulkDelete() }
        }
    }
}

extension MergedPadsView {
    /// Takes account-scoped rows rather than bare `Pad`s so each delete routes to
    /// its own row's account client, never a slug-matched guess (#758).
    func scheduleBulkDelete(_ rows: [AccountScoped<Account, Pad>]) {
        guard !rows.isEmpty else { return }

        padsPendingBulkDelete = nil
        let items = BulkDeleteUndo.mergedItems(existing: pendingBulkDeleteUndo?.items ?? [], adding: rows)
        bulkDeleteUndoTask?.cancel()
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting \(items.count) pads...")
        )
        pendingBulkDeleteUndo = pending
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil

            for row in items {
                // The grace period can outlive an account change: a row whose
                // account was removed or re-keyed meanwhile must not fire a
                // destructive delete through credentials the user just revoked
                // or replaced (#1258).
                guard let current = accounts.accounts.first(where: { $0.id == row.account.id }),
                      !current.pointsAtDifferentBackend(than: row.account) else { continue }

                await deletePad(row)
            }
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        pendingBulkDeleteUndo = nil
    }

    @ViewBuilder
    var bulkDeleteUndoBanner: some View {
        if let pendingBulkDeleteUndo {
            BulkDeleteUndoBanner(message: pendingBulkDeleteUndo.message) { cancelBulkDelete() }
        }
    }
}

extension QuestionsView {
    func scheduleBulkDelete(_ questions: [Question]) {
        guard !questions.isEmpty else { return }

        questionsPendingBulkDelete = nil
        let items = BulkDeleteUndo.mergedItems(existing: pendingBulkDeleteUndo?.items ?? [], adding: questions)
        bulkDeleteUndoTask?.cancel()
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting \(items.count) questions...")
        )
        pendingBulkDeleteUndo = pending
        // Capture the owning account now: the task can fire after an account switch,
        // and per-org question ids collide across accounts, so broadcasting under the
        // then-current account would clean up the wrong account (#1013, like #757).
        let owningAccount = accounts.currentAccountID
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil
            await bulkDelete(items, account: owningAccount)
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        pendingBulkDeleteUndo = nil
    }

    @ViewBuilder
    var bulkDeleteUndoBanner: some View {
        if let pendingBulkDeleteUndo {
            BulkDeleteUndoBanner(message: pendingBulkDeleteUndo.message) { cancelBulkDelete() }
        }
    }
}

extension MergedQuestionsView {
    func scheduleBulkDelete(_ rows: [MergedQuestionRow]) {
        guard !rows.isEmpty else { return }

        rowsPendingBulkDelete = nil
        let items = BulkDeleteUndo.mergedItems(existing: pendingBulkDeleteUndo?.items ?? [], adding: rows)
        bulkDeleteUndoTask?.cancel()
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting \(items.count) questions...")
        )
        pendingBulkDeleteUndo = pending
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil
            await bulkDelete(items)
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        pendingBulkDeleteUndo = nil
    }

    @ViewBuilder
    var bulkDeleteUndoBanner: some View {
        if let pendingBulkDeleteUndo {
            BulkDeleteUndoBanner(message: pendingBulkDeleteUndo.message) { cancelBulkDelete() }
        }
    }
}
