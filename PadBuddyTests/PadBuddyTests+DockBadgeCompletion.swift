//
//  PadBuddyTests+DockBadgeCompletion.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing
import UserNotifications

@Suite("Dock badge completion ordering")
struct DockBadgeCompletionTests {
    @Test
    func `stale completions reassert the current desired badge`() {
        #expect(badgeCompletionAction(requestGeneration: 3, currentGeneration: 4, failed: false) == .reassertCurrent)
        #expect(badgeCompletionAction(requestGeneration: 3, currentGeneration: 4, failed: true) == .reassertCurrent)
    }

    @Test
    func `only a current failed write clears the badge`() {
        #expect(
            badgeCompletionAction(requestGeneration: 4, currentGeneration: 4, failed: true) == .clearCurrentAfterFailure
        )
        #expect(badgeCompletionAction(requestGeneration: 4, currentGeneration: 4, failed: false) == .noChange)
    }
}

@Suite("Dock badge authorization and account counting")
struct DockBadgeAuthorizationTests {
    /// `refresh()` runs after any pad-cache change, including every background sweep,
    /// so the write path must never prompt: undetermined means no badge yet, and the
    /// prompt belongs to the Settings toggle's flow (#4798).
    @Test func `an undetermined status clears rather than prompting`() {
        #expect(badgeWriteDecision(for: .notDetermined) == .clear)
    }

    @Test func `a denied status clears a previously granted count`() {
        #expect(badgeWriteDecision(for: .denied) == .clear)
    }

    @Test func `an authorized status writes`() {
        #expect(badgeWriteDecision(for: .authorized) == .write)
        #expect(badgeWriteDecision(for: .provisional) == .write)
    }

    /// A repeated account record contributed its started-pad count once per
    /// occurrence (#4799).
    @Test func `a duplicated account record is counted once`() {
        let duplicated = Account(name: "Acme", apiKey: "key")
        let other = Account(name: "Other", apiKey: "key")

        let unique = uniqueBadgeAccounts([duplicated, other, duplicated])

        #expect(unique.map(\.id) == [duplicated.id, other.id])
    }

    @Test func `distinct accounts are all kept, in order`() {
        let first = Account(name: "One", apiKey: "key")
        let second = Account(name: "Two", apiKey: "key")

        #expect(uniqueBadgeAccounts([first, second]).map(\.id) == [first.id, second.id])
        #expect(uniqueBadgeAccounts([]).isEmpty)
    }
}
