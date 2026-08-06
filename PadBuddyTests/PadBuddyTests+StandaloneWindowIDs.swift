//
//  PadBuddyTests+StandaloneWindowIDs.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Standalone window identifiers")
struct StandaloneWindowIDTests {
    @Test
    func `pad identifiers reject empty restored values`() {
        #expect(!PadWindowID(account: nil, id: "").isValid)
        #expect(!PadWindowID(account: nil, id: " \n\t ").isValid)
        #expect(PadWindowID(account: nil, id: "pad-slug").isValid)
    }

    @Test
    func `question identifiers must be positive`() {
        #expect(!QuestionWindowID(account: nil, id: -1).isValid)
        #expect(!QuestionWindowID(account: nil, id: 0).isValid)
        #expect(QuestionWindowID(account: nil, id: 1).isValid)
    }

    @Test
    func `an explicit removed account is missing without using a fallback`() {
        let present = Account(name: "Present", apiKey: "key")

        #expect(StandaloneWindowAccountResolution.isExplicitTargetMissing(
            UUID(), accounts: [present]
        ))
        #expect(!StandaloneWindowAccountResolution.isExplicitTargetMissing(
            present.id, accounts: [present]
        ))
        #expect(!StandaloneWindowAccountResolution.isExplicitTargetMissing(
            nil, accounts: [present]
        ))
    }

    @Test func `a loaded account transition to nil requires standalone state reset`() {
        let id = UUID()
        #expect(StandaloneWindowAccountResolution.accountDisappeared(previous: id, current: nil))
        #expect(!StandaloneWindowAccountResolution.accountDisappeared(previous: nil, current: nil))
        #expect(!StandaloneWindowAccountResolution.accountDisappeared(previous: id, current: UUID()))
    }

    @Test func `legacy windows capture exactly the first available fallback`() {
        let first = UUID()
        #expect(StandaloneWindowAccountResolution.shouldCaptureFallback(
            explicitTarget: nil, captured: nil, current: first
        ))
        #expect(!StandaloneWindowAccountResolution.shouldCaptureFallback(
            explicitTarget: UUID(), captured: nil, current: first
        ))
        #expect(!StandaloneWindowAccountResolution.shouldCaptureFallback(
            explicitTarget: nil, captured: first, current: UUID()
        ))
        #expect(!StandaloneWindowAccountResolution.shouldCaptureFallback(
            explicitTarget: nil, captured: nil, current: nil
        ))
    }
}
