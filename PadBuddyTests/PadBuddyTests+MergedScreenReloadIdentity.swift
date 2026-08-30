//
//  PadBuddyTests+MergedScreenReloadIdentity.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Merged Screen reload identity")
struct MergedScreenReloadIdentityTests {
    @Test func `only the latest reload generation may publish`() {
        #expect(MergedScreenReloadIdentity.isCurrent(4, currentGeneration: 4))
        #expect(!MergedScreenReloadIdentity.isCurrent(3, currentGeneration: 4))
    }
}
