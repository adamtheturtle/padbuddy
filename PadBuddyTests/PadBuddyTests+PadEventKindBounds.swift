import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad event kind bounds")
struct PadEventKindBoundsTests {
    @Test func `unknown kinds have bounded safe labels and bounded cache keys`() {
        let raw = "New\n\u{202E} Kind" + String(repeating: "x", count: 10000)
        let event = PadEvent(message: "", kind: raw, metadata: nil,
                             userName: nil, userEmail: nil, createdAt: nil)
        let cache = PadEventPresentationCache()
        cache.refresh(events: [event], revision: 1)
        #expect(cache.kindLabels.keys.allSatisfy { $0.unicodeScalars.count <= 65 })
        #expect(cache.kindLabels.values.allSatisfy { $0.unicodeScalars.count <= 64 })
        let label = PadEventPresentationCache.displayKind(raw)
        #expect(!label.contains("\n"))
        #expect(!label.contains("\u{202E}"))
        #expect(PadEventPresentationCache.displayKind(" \n\u{202E}") == String(localized: "Unknown"))
    }

    @Test func `known kinds normalize without treating truncated prefixes as known events`() {
        #expect(PadEventPresentationCache.displayKind(" JOINED ")
            == PadEventPresentationCache.displayKind("joined"))
        #expect(PadEventKind.normalized("typed" + String(repeating: " ", count: 1000)) != "typed")
    }

    @Test func `event retention counts remote kind payloads toward the byte ceiling`() {
        let event = PadEvent(message: "", kind: String(repeating: "x", count: PadEventRetention.maxRetainedBytes + 1),
                             metadata: nil, userName: nil, userEmail: nil, createdAt: nil)
        #expect(PadEventRetention.newest(from: [event]).isEmpty)
    }
}
