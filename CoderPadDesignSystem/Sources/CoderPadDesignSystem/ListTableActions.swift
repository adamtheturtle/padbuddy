//
//  ListTableActions.swift
//  CoderPadDesignSystem
//

import AppKit

func availableListSelection<ID: Hashable>(_ selection: Set<ID>, availableIDs: Set<ID>) -> Set<ID> {
    selection.intersection(availableIDs)
}

func uniqueListItems<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID: Hashable {
    var seen = Set<Item.ID>()
    return items.filter { seen.insert($0.id).inserted }
}

enum ListTableUpdateKind: Equatable {
    case reload
    case refreshVisibleRows
}

func listTableUpdateKind<ID: Equatable>(oldIDs: [ID], newIDs: [ID], force: Bool) -> ListTableUpdateKind {
    force || oldIDs != newIDs ? .reload : .refreshVisibleRows
}

func configureRowMenuItem(
    _ menuItem: NSMenuItem, title: String, isDestructive: Bool, isEnabled: Bool
) {
    menuItem.title = title
    menuItem.isEnabled = isEnabled
    menuItem.setAccessibilityLabel(isDestructive ? "\(title), destructive action" : title)
    menuItem.attributedTitle = isDestructive
        ? NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
        : NSAttributedString(string: title)
}

struct ListTableDragSessionState {
    private(set) var isActive = false

    mutating func begin() {
        isActive = true
    }

    /// Returns whether the caller owns an outstanding drag-end notification.
    mutating func endIfNeeded() -> Bool {
        guard isActive else { return false }

        isActive = false
        return true
    }
}

/// One entry in a row's right-click menu, built by the caller and rendered as an `NSMenuItem`.
public enum RowMenuItem {
    case button(title: String, isDestructive: Bool = false, isEnabled: Bool = true, perform: () -> Void)
    case separator
}

/// One swipe action on a row edge, rendered as an `NSTableViewRowAction`.
public struct RowSwipeAction {
    var title: String
    var isDestructive: Bool
    var tint: NSColor?
    var systemImage: String?
    var perform: () -> Void

    public init(
        title: String,
        isDestructive: Bool = false,
        tint: NSColor? = nil,
        systemImage: String? = nil,
        perform: @escaping () -> Void
    ) {
        self.title = title
        self.isDestructive = isDestructive
        self.tint = tint
        self.systemImage = systemImage
        self.perform = perform
    }
}
