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

    func performCurrentSwipeAction(
        itemID: Item.ID,
        actionID: String,
        actionOccurrence: Int,
        edge: NSTableView.RowActionEdge
    ) {
        let currentActions = edge == .leading ? parent.leadingActions : parent.trailingActions
        resolvedRowSwipeAction(
            itemID: itemID,
            items: items,
            actionID: actionID,
            actionOccurrence: actionOccurrence,
            actions: currentActions
        )?.perform()
    }

    func performCurrentMenuAction(itemID: Item.ID, actionID: String, actionOccurrence: Int) {
        resolvedRowMenuAction(
            itemID: itemID,
            items: items,
            actionID: actionID,
            actionOccurrence: actionOccurrence,
            menuItems: parent.menuItems
        )?()
    }

    func currentMenuActionBox(itemID: Item.ID, actionID: String, actionOccurrence: Int) -> MenuActionBox {
        MenuActionBox { [weak self] in
            self?.performCurrentMenuAction(
                itemID: itemID, actionID: actionID, actionOccurrence: actionOccurrence
            )
        }
    }

    func currentMenuItem(button: RowMenuButton, itemID: Item.ID, actionOccurrence: Int) -> NSMenuItem {
        let menuItem = NSMenuItem(title: button.title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
        menuItem.target = self
        configureRowMenuItem(menuItem, button: button)
        menuItem.representedObject = currentMenuActionBox(
            itemID: itemID, actionID: button.id, actionOccurrence: actionOccurrence
        )
        return menuItem
    }
}
