import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad event date plausibility")
struct PadEventFutureDateTests {
    @Test func `future actors cannot dominate the event timeline`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func event(_ actor: String, after seconds: TimeInterval) -> PadEvent {
            PadEvent(message: "", kind: "joined", metadata: nil, userName: actor,
                     userEmail: nil, createdAt: now.addingTimeInterval(seconds))
        }
        let ordered = PadEventGrouping.chronological([
            event("Future", after: 3600), event("Current", after: 0), event("Skew", after: 60)
        ], now: now)
        #expect(ordered.compactMap(\.userName) == ["Current", "Skew"])
    }
}
