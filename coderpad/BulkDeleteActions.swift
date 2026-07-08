//
//  BulkDeleteActions.swift
//  coderpad
//

import SwiftUI

extension PadsView {
    func scheduleBulkDelete(_ pads: [Pad]) {
        guard !pads.isEmpty else { return }

        padsPendingBulkDelete = nil
        bulkDeleteUndoTask?.cancel()
        pendingBulkDeleteUndo = PendingBulkDelete(
            items: pads,
            message: String(localized: "Deleting \(pads.count) pads...")
        )
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled else { return }

            for pad in pads {
                await deletePad(pad)
            }
            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil
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
        bulkDeleteUndoTask?.cancel()
        pendingBulkDeleteUndo = PendingBulkDelete(
            items: pads,
            message: String(localized: "Deleting \(pads.count) pads...")
        )
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled else { return }

            for pad in pads {
                await deletePad(pad)
            }
            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil
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
        bulkDeleteUndoTask?.cancel()
        pendingBulkDeleteUndo = PendingBulkDelete(
            items: questions,
            message: String(localized: "Deleting \(questions.count) questions...")
        )
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled else { return }

            await bulkDelete(questions)
            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil
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
        bulkDeleteUndoTask?.cancel()
        pendingBulkDeleteUndo = PendingBulkDelete(
            items: rows,
            message: String(localized: "Deleting \(rows.count) questions...")
        )
        bulkDeleteUndoTask = Task { @MainActor in
            try? await Task.sleep(for: BulkDeleteUndo.gracePeriod)
            guard !Task.isCancelled else { return }

            await bulkDelete(rows)
            pendingBulkDeleteUndo = nil
            bulkDeleteUndoTask = nil
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
