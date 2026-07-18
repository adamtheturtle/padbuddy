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
        // Cancel only a grace timer still waiting to fire. A batch already past its
        // undo window is committed: a new batch must not silently abort its
        // remaining deletes (it has its own cancellation boundary, #1257).
        if pendingBulkDeleteUndo != nil { bulkDeleteUndoTask?.cancel() }
        let summary = BulkDeleteUndo.summary(of: items.map(\.title))
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting ^[\(items.count) pads](inflect: true): \(summary)")
        )
        pendingBulkDeleteUndo = pending
        // The doomed rows leave the list (see `filtered`) and the selection for the
        // grace period, so they can't be opened, edited, or re-selected while the
        // timer runs; Undo brings them straight back (#1262).
        selectedIDs.subtract(items.map(\.id))
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            var failedTitles: [String] = []
            var lastError: String?
            for pad in items {
                // Navigating away cancels via `onDisappear`; stop the remaining
                // destructive requests instead of firing them unobserved (#1257).
                guard !Task.isCancelled else { return }

                do {
                    try await client.deletePad(id: pad.id)
                    let owner = accounts.account(matching: client)?.id ?? accounts.currentAccountID
                    AppRouter.padDeleted(id: pad.id, account: owner)
                } catch {
                    failedTitles.append(pad.title)
                    lastError = error.localizedDescription
                }
            }
            if let lastError {
                deleteError = BulkDeleteUndo.padFailureReport(
                    failedTitles: failedTitles, total: items.count, lastError: lastError
                )
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
        // Cancel only a grace timer still waiting to fire; see `PadsView`'s note.
        if pendingBulkDeleteUndo != nil { bulkDeleteUndoTask?.cancel() }
        let summary = BulkDeleteUndo.summary(of: items.map(\.item.title))
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting ^[\(items.count) pads](inflect: true): \(summary)")
        )
        pendingBulkDeleteUndo = pending
        // Doomed rows leave the list and selection for the grace period (#1262).
        selectedIDs.subtract(items.map(\.id))
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            var failedTitles: [String] = []
            var lastError: String?
            for row in items {
                // Navigating away cancels via `onDisappear`; stop the remaining
                // destructive requests instead of firing them unobserved (#1257).
                guard !Task.isCancelled else { return }

                // The grace period can outlive an account change: a row whose
                // account was removed or re-keyed meanwhile must not fire a
                // destructive delete through credentials the user just revoked
                // or replaced (#1258).
                guard let current = accounts.accounts.first(where: { $0.id == row.account.id }),
                      !current.pointsAtDifferentBackend(than: row.account) else { continue }

                do {
                    try await row.account.makeClient().deletePad(id: row.item.id)
                    AppRouter.padDeleted(id: row.item.id, account: row.account.id)
                } catch {
                    failedTitles.append(row.item.title)
                    lastError = error.localizedDescription
                }
            }
            if let lastError {
                deleteError = BulkDeleteUndo.padFailureReport(
                    failedTitles: failedTitles, total: items.count, lastError: lastError
                )
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
        // Cancel only a grace timer still waiting to fire; see `PadsView`'s note.
        if pendingBulkDeleteUndo != nil { bulkDeleteUndoTask?.cancel() }
        let summary = BulkDeleteUndo.summary(of: items.map(\.displayTitle))
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting ^[\(items.count) questions](inflect: true): \(summary)")
        )
        pendingBulkDeleteUndo = pending
        // Doomed rows leave the list and selection for the grace period (#1262).
        selectedQuestionIDs.subtract(items.map(\.id))
        // Capture the owning account now: the task can fire after an account switch,
        // and per-org question ids collide across accounts, so broadcasting under the
        // then-current account would clean up the wrong account (#1013, like #757).
        let owningAccount = accounts.currentAccountID
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
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
        // Cancel only a grace timer still waiting to fire; see `PadsView`'s note.
        if pendingBulkDeleteUndo != nil { bulkDeleteUndoTask?.cancel() }
        let summary = BulkDeleteUndo.summary(of: items.map(\.item.displayTitle))
        let pending = PendingBulkDelete(
            items: items,
            message: String(localized: "Deleting ^[\(items.count) questions](inflect: true): \(summary)")
        )
        pendingBulkDeleteUndo = pending
        // Doomed rows leave the list and selection for the grace period (#1262).
        selectedRowIDs.subtract(items.map(\.id))
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
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
