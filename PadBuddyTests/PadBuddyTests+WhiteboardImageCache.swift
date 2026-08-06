//
//  PadBuddyTests+WhiteboardImageCache.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Whiteboard thumbnail freshness (#2096)")
struct WhiteboardImageCacheFreshnessTests {
    private let storedAt = Date(timeIntervalSinceReferenceDate: 100_000)

    /// A just-decoded thumbnail is reused as-is, so remounting the detail view
    /// doesn't pay a round-trip and an off-main re-decode per reselection.
    @Test
    func `a just-stored entry is fresh`() {
        #expect(WhiteboardImageCache.isFresh(storedAt: storedAt, now: storedAt))
        #expect(WhiteboardImageCache.isFresh(storedAt: storedAt, now: storedAt.addingTimeInterval(1)))
    }

    /// Past the window the entry revalidates again, so a drawing edited behind an
    /// unchanged URL still refreshes (#792).
    @Test
    func `an entry past the window is stale`() {
        let window = WhiteboardImageCache.freshnessWindow
        #expect(!WhiteboardImageCache.isFresh(storedAt: storedAt, now: storedAt.addingTimeInterval(window)))
        #expect(!WhiteboardImageCache.isFresh(storedAt: storedAt, now: storedAt.addingTimeInterval(window + 60)))
    }

    /// A backwards clock jump must not pin a stale drawing on screen: a future
    /// timestamp reads as stale, not as indefinitely fresh.
    @Test
    func `an entry stamped in the future is stale`() {
        #expect(!WhiteboardImageCache.isFresh(storedAt: storedAt, now: storedAt.addingTimeInterval(-1)))
    }

    @Test
    func `cache keys do not retain signed URLs`() throws {
        let url = try #require(URL(string: "https://images.example.com/board.png?token=very-secret"))
        let key = WhiteboardImageCache.cacheKey(url: url)
        #expect(!key.contains("very-secret"))
        #expect(key == WhiteboardImageCache.cacheKey(url: url))
        #expect(key.count == 64)
    }
}
