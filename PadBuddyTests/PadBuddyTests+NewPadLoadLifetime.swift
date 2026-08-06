//
//  PadBuddyTests+NewPadLoadLifetime.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("New Pad load lifetime")
struct NewPadLoadLifetimeTests {
    @Test
    func `dismissal invalidates in-flight load claims`() {
        var lifetime = NewPadLoadLifetime()
        let claim = lifetime.revision

        lifetime.invalidate()

        #expect(!lifetime.isCurrent(claim, taskIsCancelled: false))
        #expect(!lifetime.isActive)
    }

    @Test
    func `a remounted sheet accepts only its new load claims`() {
        var lifetime = NewPadLoadLifetime()
        let oldClaim = lifetime.revision
        lifetime.invalidate()
        lifetime.activate()
        let newClaim = lifetime.revision

        #expect(!lifetime.isCurrent(oldClaim, taskIsCancelled: false))
        #expect(lifetime.isCurrent(newClaim, taskIsCancelled: false))
        #expect(!lifetime.isCurrent(newClaim, taskIsCancelled: true))
    }
}
