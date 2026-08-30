//
//  PadBuddyTests+AccountMemberLoadIdentity.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Account member load identity")
struct AccountMemberLoadIdentityTests {
    @Test
    func `only the latest member load owns published state`() {
        #expect(AccountEditor.memberLoadIsCurrent(4, currentGeneration: 4))
        #expect(!AccountEditor.memberLoadIsCurrent(3, currentGeneration: 4))
    }
}
