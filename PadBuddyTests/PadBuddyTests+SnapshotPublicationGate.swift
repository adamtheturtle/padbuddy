import Foundation
@testable import PadBuddy
import Testing

@Suite("Progressive snapshot publication")
nonisolated struct SnapshotPublicationGateTests {
    @Test func `first progress is immediate and rapid pages share one publication window`() {
        let start = ContinuousClock.now
        var gate = SnapshotPublicationGate()
        let publications = [
            gate.shouldPublish(at: start), gate.shouldPublish(at: start),
            gate.shouldPublish(at: start.advanced(by: .milliseconds(199))),
            gate.shouldPublish(at: start.advanced(by: .milliseconds(200))),
            gate.shouldPublish(at: start.advanced(by: .milliseconds(399))),
            gate.shouldPublish(at: start.advanced(by: .milliseconds(400)))
        ]
        #expect(publications == [true, false, false, true, false, true])
    }

    @Test func `a slow page opens a fresh window without catch up publications`() {
        let start = ContinuousClock.now
        var gate = SnapshotPublicationGate()
        let first = gate.shouldPublish(at: start)
        let later = start.advanced(by: .seconds(10))
        let slow = gate.shouldPublish(at: later)
        let next = gate.shouldPublish(at: later.advanced(by: .milliseconds(1)))
        #expect([first, slow, next] == [true, true, false])
    }
}
