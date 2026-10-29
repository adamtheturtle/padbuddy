import Foundation
@testable import PadBuddy
import Testing

@Suite("History timestamp admission")
struct HistoryTimestampAdmissionTests {
    @Test func `large backwards jumps are rejected while small clock skew is lifted`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let previous: Int64 = 1_699_000_000_000
        #expect(PadHistoryTimestampPolicy.admitted(previous - 60000, after: previous, now: now) == previous)
        #expect(PadHistoryTimestampPolicy.admitted(previous - 3_600_000, after: previous, now: now) == nil)
    }

    @Test func `invalid timestamps are rejected before their edits enter checkpoints`() {
        let history = PadHistory(entries: [
            PadHistoryEntry(id: "a", author: "Ada", operations: [.insert("invalid")], timestamp: -1),
            PadHistoryEntry(id: "b", author: "Ada", operations: [.insert("later")], timestamp: 1000)
        ])
        let built = PadHistoryBuild(history: history)
        #expect(built.snapshots.isEmpty)
        #expect(built.checkpoints.isEmpty)
        #expect(built.wasTruncated)
    }
}
