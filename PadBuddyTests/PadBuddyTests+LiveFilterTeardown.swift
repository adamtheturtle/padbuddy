import Foundation
@testable import PadBuddy
import Testing

@Suite("Live filter account teardown")
@MainActor
struct LiveFilterTeardownTests {
    @Test func `removed account writes are discarded across windows without affecting another account`() {
        let persistence = LiveFilterPersistence()
        let removed = UUID(), remaining = UUID()
        var written: [String] = []
        let padKey = "pads.liveFilter.\(removed.uuidString)"
        let questionKey = "questions.liveFilter.\(removed.uuidString)"
        persistence.schedule(key: padKey) { written.append("pad") }
        persistence.schedule(key: LiveFilterPersistence.debounceKey(storageKey: questionKey, scope: UUID())) {
            written.append("question")
        }
        persistence.schedule(key: "pads.liveFilter.\(remaining.uuidString)") { written.append("remaining") }
        persistence.cancel(account: removed)
        persistence.flushAll()
        #expect(written == ["remaining"])
    }
}
