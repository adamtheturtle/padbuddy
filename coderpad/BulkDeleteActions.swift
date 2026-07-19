//
//  BulkDeleteActions.swift
//  coderpad
//
//  The pad bulk-delete flows. The question ones live in
//  BulkDeleteActions+Questions.swift, split to keep both files under the
//  file-length limit.
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
        // timer runs; Undo brings them straight back (#1262, #2348).
        selectedIDs.subtract(items.map(\.id))
        // The account this batch belongs to, snapshotted now. The grace period can
        // outlive an account change, and a batch scheduled under one account's
        // credentials must not fire through a key the user has since replaced or
        // revoked (#2344) — the merged flow has guarded this since #1258.
        let owningAccount = accounts.account(matching: client)
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled, pendingBulkDeleteUndo?.id == pending.id else { return }

            pendingBulkDeleteUndo = nil
            guard BulkDeleteUndo.accountStillUsable(owningAccount, in: accounts) else {
                deleteError = BulkDeleteUndo.credentialsChangedReport
                return
            }

            let outcome = await BulkDeleteRunner.run(
                items,
                title: \.title,
                onProgress: { bulkDeleteProgress = $0 },
                delete: { pad in
                    do {
                        try await client.deletePad(id: pad.id)
                        let owner = accounts.account(matching: client)?.id ?? accounts.currentAccountID
                        AppRouter.padDeleted(id: pad.id, account: owner, via: client)
                        return nil
                    } catch {
                        return error
                    }
                }
            )
            bulkDeleteProgress = nil
            deleteError = BulkDeleteUndo.report(outcome, total: items.count, kind: .pads)
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        // Undo puts the selection back the way it was, so the user can adjust it and
        // try again instead of hunting down and re-picking every row (#2348).
        if let pending = pendingBulkDeleteUndo {
            selectedIDs.formUnion(pending.items.map(\.id))
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
            let live = accounts
            let outcome = await BulkDeleteRunner.run(
                items,
                title: \.item.title,
                onProgress: { bulkDeleteProgress = $0 },
                delete: { row in
                    // The grace period can outlive an account change: a row whose
                    // account was removed or re-keyed meanwhile must not fire a
                    // destructive delete through credentials the user just revoked
                    // or replaced (#1258).
                    guard let current = live.accounts.first(where: { $0.id == row.account.id }),
                          !current.pointsAtDifferentBackend(than: row.account) else { return nil }

                    do {
                        let client = current.makeClient()
                        try await client.deletePad(id: row.item.id)
                        AppRouter.padDeleted(id: row.item.id, account: row.account.id, via: client)
                        return nil
                    } catch {
                        return error
                    }
                }
            )
            bulkDeleteProgress = nil
            deleteError = BulkDeleteUndo.report(outcome, total: items.count, kind: .pads)
        }
    }

    func cancelBulkDelete() {
        bulkDeleteUndoTask?.cancel()
        bulkDeleteUndoTask = nil
        // Undo restores the selection it took away (#2348).
        if let pending = pendingBulkDeleteUndo {
            selectedIDs.formUnion(pending.items.map(\.id))
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
