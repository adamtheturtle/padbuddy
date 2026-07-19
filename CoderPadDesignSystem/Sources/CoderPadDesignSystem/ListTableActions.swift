//
//  ListTableActions.swift
//  CoderPadDesignSystem
//

import AppKit

func availableListSelection<ID: Hashable>(_ selection: Set<ID>, availableIDs: Set<ID>) -> Set<ID> {
    selection.intersection(availableIDs)
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
