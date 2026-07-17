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
