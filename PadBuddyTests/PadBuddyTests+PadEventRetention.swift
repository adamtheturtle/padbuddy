//
//  PadBuddyTests+PadEventRetention.swift
//  PadBuddyTests
//

import CoderPadKit
@testable import PadBuddy
import Testing

@Suite("Pad event retention")
struct PadEventRetentionTests {
    private func event(message: String) -> PadEvent {
        PadEvent(message: message, kind: "ran", metadata: nil,
                 userName: "Basil", userEmail: nil, createdAt: nil)
    }

    @Test
    func `retains only the newest count-bounded prefix`() {
        let events = (0 ... PadEventRetention.maxEventCount).map { event(message: "event-\($0)") }

        let retained = PadEventRetention.newest(from: events)

        #expect(retained.count == PadEventRetention.maxEventCount)
        #expect(retained.first?.message == "event-0")
        #expect(retained.last?.message == "event-4999")
    }

    @Test
    func `stops before retained event strings exceed the byte budget`() {
        let message = String(repeating: "x", count: PadEventRetention.maxRetainedBytes / 2)

        #expect(PadEventRetention.newest(from: [event(message: message), event(message: message)]).count == 1)
    }
}
