//
//  PadBuddyTests+ScreenRetention.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Screen test retention")
struct ScreenTestRetentionTests {
    @Test
    func `small result sets retain their server order`() {
        let sessions = [session(id: 1, activity: 10), session(id: 2, activity: 20)]
        let result = ScreenTestRetention.newest(sessions)

        #expect(result.sessions.map(\.id) == [1, 2])
        #expect(result.omitted == 0)
    }

    @Test
    func `large result sets retain only the newest sessions`() {
        let sessions = (0 ... ScreenTestRetention.maximumSessions).map {
            session(id: $0, activity: $0)
        }
        let result = ScreenTestRetention.newest(sessions)

        #expect(result.sessions.count == ScreenTestRetention.maximumSessions)
        #expect(result.omitted == 1)
        #expect(result.sessions.first?.id == ScreenTestRetention.maximumSessions)
        #expect(!result.sessions.contains(where: { $0.id == 0 }))
    }

    @Test
    func `equal activity times use identity as a deterministic tie break`() {
        var sessions = (1 ... ScreenTestRetention.maximumSessions).map {
            session(id: $0, activity: 100)
        }
        sessions.append(session(id: 10000, activity: 100))

        let result = ScreenTestRetention.newest(sessions)
        #expect(result.sessions.first?.id == 10000)
        #expect(!result.sessions.contains(where: { $0.id == 1 }))
    }

    private func session(id: Int, activity: Int) -> ScreenTestSession {
        ScreenTestSession(id: id, lastActivityTime: activity)
    }
}
