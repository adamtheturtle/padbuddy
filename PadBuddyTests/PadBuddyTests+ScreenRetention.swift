//
//  PadBuddyTests+ScreenRetention.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Screen test retention")
struct ScreenTestRetentionTests {
    @Test
    func `small result sets retain their server order`() throws {
        let sessions = try [session(id: 1, activity: 10), session(id: 2, activity: 20)]
        let result = ScreenTestRetention.newest(sessions)

        #expect(result.sessions.map(\.id) == [1, 2])
        #expect(result.omitted == 0)
    }

    /// Ids start at 1: CoderPadKit rejects a non-positive Screen model id outright,
    /// so 0 is no longer a constructible session.
    @Test
    func `large result sets retain only the newest sessions`() throws {
        let newest = ScreenTestRetention.maximumSessions + 1
        let sessions = try (1 ... newest).map {
            try session(id: $0, activity: $0)
        }
        let result = ScreenTestRetention.newest(sessions)

        #expect(result.sessions.count == ScreenTestRetention.maximumSessions)
        #expect(result.omitted == 1)
        #expect(result.sessions.first?.id == newest)
        #expect(!result.sessions.contains(where: { $0.id == 1 }))
    }

    @Test
    func `equal activity times use identity as a deterministic tie break`() throws {
        var sessions = try (1 ... ScreenTestRetention.maximumSessions).map {
            try session(id: $0, activity: 100)
        }
        try sessions.append(session(id: 10000, activity: 100))

        let result = ScreenTestRetention.newest(sessions)
        #expect(result.sessions.first?.id == 10000)
        #expect(!result.sessions.contains(where: { $0.id == 1 }))
    }

    /// Screen timestamps are validated as plausible epoch milliseconds, so `activity`
    /// is an offset from a real instant rather than a bare counter.
    private func session(id: Int, activity: Int) throws -> ScreenTestSession {
        try ScreenTestSession(id: id, lastActivityTime: 1_700_000_000_000 + activity)
    }
}
