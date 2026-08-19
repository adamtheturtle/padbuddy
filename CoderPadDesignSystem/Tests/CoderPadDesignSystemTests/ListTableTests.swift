//
//  ListTableTests.swift
//  CoderPadDesignSystemTests
//

import AppKit
@testable import CoderPadDesignSystem
import Testing

@Suite("ListTable state")
struct ListTableTests {
    private struct Item: Identifiable, Equatable {
        let id: Int
        let value: String
    }

    @Test(arguments: [
        NSEvent.ModifierFlags.command,
        .option,
        .shift,
        .control
    ])
    func `modified Return is left to AppKit`(modifier: NSEvent.ModifierFlags) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifier,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))

        #expect(!KeyHandlingTableView.handlesReturn(event))
    }

    @Test(arguments: [(UInt16(36), NSEvent.ModifierFlags()), (UInt16(76), .numericPad)])
    func `unmodified Return and keypad Enter open the row`(keyCode: UInt16, flags: NSEvent.ModifierFlags) throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: keyCode
        ))

        #expect(KeyHandlingTableView.handlesReturn(event))
    }

    @Test
    func `selection is limited to available row IDs`() {
        #expect(availableListSelection(Set([1, 2]), availableIDs: Set([1])) == Set([1]))
        #expect(availableListSelection(Set([3]), availableIDs: Set<Int>()).isEmpty)
    }

    @Test
    func `duplicate row IDs keep only the first item`() {
        let items = [Item(id: 1, value: "first"), Item(id: 1, value: "duplicate"), Item(id: 2, value: "second")]

        #expect(uniqueListItems(items) == [items[0], items[2]])
    }

    @Test
    func `stable IDs refresh visible content while structural changes reload`() {
        #expect(listTableUpdateKind(oldIDs: [1, 2], newIDs: [1, 2], force: false) == .refreshVisibleRows)
        #expect(listTableUpdateKind(oldIDs: [1, 2], newIDs: [2, 1], force: false) == .reload)
        #expect(listTableUpdateKind(oldIDs: [1, 2], newIDs: [1, 2], force: true) == .reload)
    }

    @Test
    func `top row clears exactly on nonempty to empty transitions`() {
        #expect(shouldClearListTopRow(oldItemCount: 2, newItemCount: 0))
        #expect(!shouldClearListTopRow(oldItemCount: 0, newItemCount: 0))
        #expect(!shouldClearListTopRow(oldItemCount: 0, newItemCount: 2))
        #expect(!shouldClearListTopRow(oldItemCount: 2, newItemCount: 1))
        #expect(shouldClearListTopRow(oldItemCount: 1, newItemCount: 0))
    }

    @Test
    func `drag end cleanup is emitted once after a drag begins`() {
        var state = ListTableDragSessionState()

        let endedBeforeBeginning = state.endIfNeeded()
        #expect(!endedBeforeBeginning)
        state.begin()
        #expect(state.isActive)
        let endedActiveDrag = state.endIfNeeded()
        #expect(endedActiveDrag)
        #expect(!state.isActive)
        let endedTwice = state.endIfNeeded()
        #expect(!endedTwice)
    }

    @Test
    func `destructive menu metadata is presented visually and accessibly`() {
        let item = NSMenuItem()

        configureRowMenuItem(item, title: "Delete", isDestructive: true, isEnabled: false)

        let foreground = item.attributedTitle?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(foreground == .systemRed)
        #expect(item.accessibilityLabel() == "Delete, destructive action")
        #expect(!item.isEnabled)
    }

    @Test
    func `swipe action resolves against the current row snapshot`() {
        let original = Item(id: 1, value: "original")
        let refreshed = Item(id: 1, value: "refreshed")
        var performedValue: String?
        let actions: (Item) -> [RowSwipeAction] = { item in
            [RowSwipeAction(title: "Run", id: "run") { performedValue = item.value }]
        }

        resolvedRowSwipeAction(itemID: original.id, items: [refreshed], actionID: "run", actions: actions)?.perform()
        #expect(performedValue == "refreshed")
        #expect(resolvedRowSwipeAction(itemID: original.id, items: [], actionID: "run", actions: actions) == nil)
        #expect(
            resolvedRowSwipeAction(itemID: original.id, items: [refreshed], actionID: "gone", actions: actions) == nil
        )
    }

    @Test
    func `duplicate swipe titles dispatch their represented occurrence`() {
        let item = Item(id: 1, value: "current")
        var performed: String?
        let actions: (Item) -> [RowSwipeAction] = { _ in
            [
                RowSwipeAction(title: "Run") { performed = "first" },
                RowSwipeAction(title: "Run") { performed = "second" }
            ]
        }

        resolvedRowSwipeAction(
            itemID: item.id,
            items: [item],
            actionID: "Run",
            actionOccurrence: 1,
            actions: actions
        )?.perform()

        #expect(performed == "second")
    }

    @Test
    func `menu action resolves against the current row snapshot`() {
        let refreshed = Item(id: 1, value: "refreshed")
        var performedValue: String?
        let menuItems: (Item) -> [RowMenuItem] = { item in
            [.button(title: "Run", id: "run") { performedValue = item.value }]
        }

        resolvedRowMenuAction(itemID: 1, items: [refreshed], actionID: "run", menuItems: menuItems)?()
        #expect(performedValue == "refreshed")
        #expect(resolvedRowMenuAction(itemID: 1, items: [], actionID: "run", menuItems: menuItems) == nil)
        #expect(resolvedRowMenuAction(itemID: 1, items: [refreshed], actionID: "gone", menuItems: menuItems) == nil)
    }

    @Test
    func `duplicate menu titles dispatch their represented occurrence`() {
        let item = Item(id: 1, value: "current")
        var performed: String?
        let menuItems: (Item) -> [RowMenuItem] = { _ in
            [
                .button(title: "Run") { performed = "first" },
                .separator,
                .button(title: "Run") { performed = "second" }
            ]
        }

        resolvedRowMenuAction(
            itemID: item.id,
            items: [item],
            actionID: "Run",
            actionOccurrence: 1,
            menuItems: menuItems
        )?()

        #expect(performed == "second")
    }
}
