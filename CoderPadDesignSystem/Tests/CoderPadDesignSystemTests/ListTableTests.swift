//
//  ListTableTests.swift
//  CoderPadDesignSystemTests
//

@testable import CoderPadDesignSystem
import Testing

@Suite("ListTable state")
struct ListTableTests {
    @Test
    func `selection is limited to available row IDs`() {
        #expect(availableListSelection(Set([1, 2]), availableIDs: Set([1])) == Set([1]))
        #expect(availableListSelection(Set([3]), availableIDs: Set<Int>()).isEmpty)
    }
}
