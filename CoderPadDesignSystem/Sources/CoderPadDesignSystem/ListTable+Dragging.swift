//
//  ListTable+Dragging.swift
//  CoderPadDesignSystem
//

import AppKit

extension ListTable.Coordinator {
    func resetScrollRequest() {
        activeScrollRequestID = nil
    }

    func endDragIfNeeded() {
        guard dragSessionState.endIfNeeded() else { return }

        parent.onDragSessionEnded()
    }

    func performCurrentSwipeAction(itemID: Item.ID, actionID: String, edge: NSTableView.RowActionEdge) {
        let currentActions = edge == .leading ? parent.leadingActions : parent.trailingActions
        resolvedRowSwipeAction(itemID: itemID, items: items, actionID: actionID, actions: currentActions)?.perform()
    }
}
