//
//  ListTable+Dragging.swift
//  CoderPadDesignSystem
//

extension ListTable.Coordinator {
    func resetScrollRequest() {
        activeScrollRequestID = nil
    }

    func endDragIfNeeded() {
        guard dragSessionState.endIfNeeded() else { return }

        parent.onDragSessionEnded()
    }
}
