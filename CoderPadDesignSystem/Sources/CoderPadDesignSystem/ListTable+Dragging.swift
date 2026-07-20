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

    func performCurrentMenuAction(itemID: Item.ID, actionID: String) {
        resolvedRowMenuAction(itemID: itemID, items: items, actionID: actionID, menuItems: parent.menuItems)?()
    }

    func currentMenuActionBox(itemID: Item.ID, actionID: String) -> MenuActionBox {
        MenuActionBox { [weak self] in
            self?.performCurrentMenuAction(itemID: itemID, actionID: actionID)
        }
    }

    func currentMenuItem(button: RowMenuButton, itemID: Item.ID) -> NSMenuItem {
        let menuItem = NSMenuItem(title: button.title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
        menuItem.target = self
        configureRowMenuItem(menuItem, button: button)
        menuItem.representedObject = currentMenuActionBox(itemID: itemID, actionID: button.id)
        return menuItem
    }
}
