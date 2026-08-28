//
//  PadBuddyTests+WhiteboardImageCache.swift
//  PadBuddyTests
//

import Foundation
import Nuke
@testable import PadBuddy
import SafeURLKit
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

@Suite("Whiteboard transport policy (#4599, #4600, #4601)")
@MainActor
struct WhiteboardTransportPolicyTests {
    @Test func `the URL cache keeps nothing on disk`() {
        // Whiteboard export URLs carry their signature in the query, and URLCache writes
        // request URLs and their responses to disk verbatim.
        let cache = WhiteboardImageCache()

        #expect(cache.pipeline.configuration.dataLoader is DataLoader)
        let loader = cache.pipeline.configuration.dataLoader as? DataLoader
        #expect(loader?.session.configuration.urlCache?.diskCapacity == 0)
    }

    @Test func `redirects are re-checked against the image URL policy`() {
        let cache = WhiteboardImageCache()
        let loader = cache.pipeline.configuration.dataLoader as? DataLoader

        // Without a redirect delegate, an allowed public HTTPS URL could redirect to
        // loopback, a LAN address, or plain HTTP with nothing re-validating it.
        #expect(loader?.delegate is PolicyEnforcingRedirectDelegate)
    }

    @Test(arguments: [
        "http://example.com/board.png", "https://localhost/board.png",
        "https://127.0.0.1/board.png", "https://169.254.169.254/board.png",
        "https://user:secret@example.com/board.png"
    ])
    func `the image URL policy refuses unsafe destinations`(url: String) throws {
        let candidate = try #require(URL(string: url))

        #expect(!WhiteboardImage.isAllowedImageURL(candidate))
    }

    @Test func `a signed public HTTPS export is allowed`() throws {
        let candidate = try #require(URL(string: "https://coderpad.io/board.png?sig=abc"))

        #expect(WhiteboardImage.isAllowedImageURL(candidate))
    }
}
