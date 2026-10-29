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

    @Test
    func `duplicate IDs keep the newest copy and preserve small response order`() throws {
        let sessions = try [session(id: 1, activity: 10), session(id: 2, activity: 20),
                            session(id: 1, activity: 30), session(id: 2, activity: 5)]
        let result = ScreenTestRetention.newest(sessions)
        #expect(result.sessions.map(\.id) == [1, 2])
        #expect(result.sessions.map(\.lastActivityTime) == [1_700_000_000_030, 1_700_000_000_020])
        #expect(result.omitted == 2)
    }

    @Test
    func `evicted identities can return with newer data without duplicate rows`() throws {
        var sessions = try (1 ... 5000).map { try session(id: $0, activity: $0) }
        try sessions.append(session(id: 1, activity: 10000))
        try sessions.append(session(id: 5000, activity: 20000))
        try sessions.append(session(id: 1, activity: 1))
        let result = ScreenTestRetention.newest(sessions)
        #expect(result.sessions.count == 1000)
        #expect(Set(result.sessions.map(\.id)).count == 1000)
        #expect(result.sessions.prefix(2).map(\.id) == [5000, 1])
        #expect(result.sessions.last?.id == 4002)
        #expect(result.omitted == 4003)
    }

    @Test
    func `bounded selection matches a reference sort for mixed duplicates`() throws {
        let sessions = try (1 ... 12000).map { index in
            try session(id: index % 1700 + 1, activity: index * 37 % 10000)
        }
        var latest: [Int: ScreenTestSession] = [:]
        for session in sessions where (latest[session.id]?.lastActivityTime ?? Int.min)
            < (session.lastActivityTime ?? Int.min) {
            latest[session.id] = session
        }
        let expected = latest.values.sorted {
            $0.lastActivityTime == $1.lastActivityTime
                ? $0.id > $1.id : ($0.lastActivityTime ?? Int.min) > ($1.lastActivityTime ?? Int.min)
        }.prefix(1000)
        let result = ScreenTestRetention.newest(sessions)
        #expect(result.sessions.map(\.id) == expected.map(\.id))
        #expect(result.sessions.map(\.lastActivityTime) == expected.map(\.lastActivityTime))
    }

    /// Screen timestamps are validated as plausible epoch milliseconds, so `activity`
    /// is an offset from a real instant rather than a bare counter.
    private func session(id: Int, activity: Int) throws -> ScreenTestSession {
        try ScreenTestSession(id: id, lastActivityTime: 1_700_000_000_000 + activity)
    }
}
