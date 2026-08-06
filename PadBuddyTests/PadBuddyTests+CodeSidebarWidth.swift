//
//  PadBuddyTests+CodeSidebarWidth.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Code sidebar width")
struct CodeSidebarWidthTests {
    @Test
    func `persisted widths are bounded and nonfinite values recover`() {
        #expect(CodeSidebarWidth.clamped(0) == CodeSidebarWidth.minimum)
        #expect(CodeSidebarWidth.clamped(10000) == CodeSidebarWidth.maximum)
        #expect(CodeSidebarWidth.clamped(.nan) == CodeSidebarWidth.defaultValue)
        #expect(CodeSidebarWidth.clamped(.infinity) == CodeSidebarWidth.defaultValue)
        #expect(CodeSidebarWidth.clamped(240) == 240)
    }

    @Test
    func `effective width reserves code space without changing wide preferences`() {
        #expect(CodeSidebarWidth.effective(420, availableWidth: 1000) == 420)
        #expect(CodeSidebarWidth.effective(420, availableWidth: 500) == 280)
        #expect(CodeSidebarWidth.effective(420, availableWidth: 300) == CodeSidebarWidth.minimum)
        #expect(CodeSidebarWidth.effective(240, availableWidth: .nan) == 240)
    }
}
