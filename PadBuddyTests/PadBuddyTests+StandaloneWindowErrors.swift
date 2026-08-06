//
//  PadBuddyTests+StandaloneWindowErrors.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Standalone window refresh errors")
struct StandaloneWindowRefreshErrorTests {
    @Test
    func `uses resource-specific recovery copy`() {
        let messages = [
            StandaloneWindowRefreshError.pad.message,
            StandaloneWindowRefreshError.question.message,
            StandaloneWindowRefreshError.screenTest.message
        ]

        #expect(messages.allSatisfy { !$0.isEmpty })
        #expect(Set(messages).count == messages.count)
    }
}
