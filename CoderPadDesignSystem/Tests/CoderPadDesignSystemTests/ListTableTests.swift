//
//  ListTableTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import Testing

@Suite("ListTable state")
struct ListTableTests {
    private struct Item: Identifiable, Equatable {
        let id: Int
        let value: String
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
}
