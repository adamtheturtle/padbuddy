//
//  PadBuddyTests+AppStateRestorationReset.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Restored app state reset")
struct AppStateRestorationResetTests {
    @Test func `sidebar layout is restored state`() {
        #expect(AppStateRestorationReset.includes(key: "sidebar.collapsed"))
    }

    @Test func `focus filter stack is restored state`() {
        #expect(AppStateRestorationReset.includes(key: "focusFilter.scopeStack.v2"))
    }

    @Test func `unrelated preferences are not restored state`() {
        #expect(!AppStateRestorationReset.includes(key: "general.appearance"))
        #expect(!AppStateRestorationReset.includes(key: "accounts"))
    }
}
