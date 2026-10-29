import Foundation
@testable import PadBuddy
import Testing

@Suite("Participant refresh failures")
@MainActor
struct ParticipantRefreshFailureTests {
    @Test func `network failure and mismatched pad identity remain distinguishable from success`() async {
        let failed = await PadParticipantRefresh.load(id: "ABC123") { _ in throw URLError(.timedOut) }
        let wrong = await PadParticipantRefresh.load(id: "ABC123") { _ in Pad(id: "XYZ789", title: "Wrong") }
        let pad = Pad(id: "ABC123", title: "Current")
        let success = await PadParticipantRefresh.load(id: "ABC123") { _ in pad }
        #expect(failed == .failed)
        #expect(wrong == .failed)
        #expect(success == .loaded(pad))
    }

    @Test func `cancellation does not claim a participant refresh failure`() async {
        let cancelled = await PadParticipantRefresh.load(id: "ABC123") { _ in throw CancellationError() }
        #expect(cancelled == .cancelled)
    }
}
