//
//  coderpadTests+PadEventGrouping.swift
//  coderpadTests
//
//  Split out of coderpadTests+PadListLogic.swift to keep both files under the
//  SwiftLint file-length limit.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Pad event grouping")
struct PadEventGroupingTests {
    private func event(_ kind: String, user: String?, at seconds: TimeInterval, email: String? = nil) -> PadEvent {
        PadEvent(message: "m", kind: kind, metadata: nil, userName: user,
                 userEmail: email, createdAt: Date(timeIntervalSince1970: seconds))
    }

    @Test
    func `an empty log produces no groups`() {
        #expect(PadEventGrouping.group([]).isEmpty)
    }

    @Test
    func `consecutive same-kind, same-user events collapse into one group`() {
        let events = [
            event("typed", user: "Alex", at: 1),
            event("typed", user: "Alex", at: 2),
            event("typed", user: "Alex", at: 3)
        ]
        let groups = PadEventGrouping.group(events)
        #expect(groups.count == 1)
        #expect(groups[0].count == 3)
        // The representative is the first event; lastEvent is the most recent.
        #expect(groups[0].representative.createdAt == Date(timeIntervalSince1970: 1))
        #expect(groups[0].lastEvent.createdAt == Date(timeIntervalSince1970: 3))
    }

    @Test func `out-of-order API events are grouped chronologically`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 3),
            event("started", user: "Alex", at: 1),
            event("typed", user: "Alex", at: 2)
        ])
        #expect(groups.map(\.representative.kind) == ["started", "typed"])
        #expect(groups.map(\.count) == [1, 2])
        #expect(groups[1].representative.createdAt == Date(timeIntervalSince1970: 2))
        #expect(groups[1].lastEvent.createdAt == Date(timeIntervalSince1970: 3))
    }

    @Test func `equal timestamps retain API order and undated events follow dated events`() {
        let undated = PadEvent(message: "undated", kind: "ended", metadata: nil, userName: "Alex",
                               userEmail: nil, createdAt: nil)
        let groups = PadEventGrouping.group([
            undated,
            event("joined", user: "Alex", at: 1),
            event("left", user: "Alex", at: 1)
        ])
        #expect(groups.map(\.representative.kind) == ["joined", "left", "ended"])
    }

    @Test
    func `a different user breaks the run`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 1),
            event("typed", user: "Sam", at: 2)
        ])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test
    func `a different email breaks the run even with missing display names`() {
        let groups = PadEventGrouping.group([
            event("typed", user: nil, at: 1, email: "first@example.com"),
            event("typed", user: nil, at: 2, email: "second@example.com")
        ])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test
    func `a different email breaks the run even with the same display name`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 1, email: "first@example.com"),
            event("typed", user: "Alex", at: 2, email: "second@example.com")
        ])
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { $0.count == 1 })
    }

    @Test
    func `the same email collapses the run without display names`() {
        let groups = PadEventGrouping.group([
            event("typed", user: nil, at: 1, email: "Alex@Example.com"),
            event("typed", user: nil, at: 2, email: "alex@example.com")
        ])
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
    }

    @Test
    func `the same display name collapses the run regardless of case`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alice", at: 1),
            event("typed", user: "alice", at: 2)
        ])
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)
    }

    @Test
    func `a different kind breaks the run even when both kinds are collapsible`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 1),
            event("edited", user: "Alex", at: 2)
        ])
        #expect(groups.count == 2)
    }

    @Test
    func `non-collapsible kinds are never merged`() {
        // Two consecutive joins by the same user remain two distinct rows.
        let groups = PadEventGrouping.group([
            event("joined", user: "Alex", at: 1),
            event("joined", user: "Alex", at: 2)
        ])
        #expect(groups.count == 2)
    }

    @Test
    func `a collapsible run is bracketed by lifecycle events`() {
        let groups = PadEventGrouping.group([
            event("started", user: "Alex", at: 1),
            event("ran", user: "Alex", at: 2),
            event("ran", user: "Alex", at: 3),
            event("ended", user: "Alex", at: 4)
        ])
        // started (1) + collapsed ran×2 (1) + ended (1) = three groups.
        #expect(groups.map(\.count) == [1, 2, 1])
        #expect(groups.map(\.representative.kind) == ["started", "ran", "ended"])
    }

    @Test
    func `a long idle gap breaks a collapsible run`() {
        let gap = PadEventGrouping.maxCollapseGap
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 0),
            event("typed", user: "Alex", at: gap),
            event("typed", user: "Alex", at: gap * 3)
        ])

        // The first two are within the gap; the third resumes hours later.
        #expect(groups.map(\.count) == [2, 1])
    }

    @Test
    func `undated events still collapse`() {
        let undated = PadEvent(message: "m", kind: "typed", metadata: nil, userName: "Alex",
                               userEmail: nil, createdAt: nil)
        #expect(PadEventGrouping.group([undated, undated]).map(\.count) == [2])
    }

    @Test
    func `a large backwards jump breaks the run`() {
        let groups = PadEventGrouping.group([
            event("typed", user: "Alex", at: 100_000),
            event("typed", user: "Alex", at: 1)
        ])

        #expect(groups.count == 2)
    }

    @Test
    func `group identities stay bounded and free of control characters`() {
        let noisy = PadEvent(message: String(repeating: "x", count: 5000) + "\n\u{07}done",
                             kind: "joined", metadata: nil, userName: "Alex",
                             userEmail: nil, createdAt: Date(timeIntervalSince1970: 1))
        let groups = PadEventGrouping.group([noisy])

        #expect(groups.count == 1)
        let id = groups.first?.id ?? ""
        #expect(id.hasPrefix("0-"))
        #expect(id.count <= 2 + PadEventGrouping.maxIdentitySuffixLength)
        let containsNewline = id.contains(where: \.isNewline)
        #expect(!containsNewline)
    }

    @Test
    func `identities stay unique once the event part is truncated`() {
        // Two events whose IDs only differ past the cap must still be distinct
        // rows, which the positional prefix guarantees.
        let shared = String(repeating: "y", count: 200)
        let groups = PadEventGrouping.group([
            PadEvent(message: shared + "first", kind: "joined", metadata: nil, userName: "Alex",
                     userEmail: nil, createdAt: Date(timeIntervalSince1970: 1)),
            PadEvent(message: shared + "second", kind: "joined", metadata: nil, userName: "Alex",
                     userEmail: nil, createdAt: Date(timeIntervalSince1970: 1))
        ])

        #expect(groups.count == 2)
        #expect(groups[0].id != groups[1].id)
    }
}
