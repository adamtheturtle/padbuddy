//
//  PadBuddyTests+PadDetailCacheBounds.swift
//  PadBuddyTests
//

import CoderPadKit
import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad detail cache bounds")
@MainActor
struct PadDetailCacheBoundsTests {
    private func event(message: String) -> PadEvent {
        PadEvent(message: message, kind: "ran", metadata: nil,
                 userName: "Basil", userEmail: nil, createdAt: nil)
    }

    /// Events were charged a flat 200 bytes each, so a pad whose log carries long
    /// server-provided messages was admitted far past the byte cap and pinned for the
    /// session — the case the cap exists for (#4806).
    @Test func `an entry whose events exceed the byte cap is not cached`() throws {
        let store = PadDetailCacheStore.shared
        let client = try CoderPadClient.live(
            apiKey: "key-\(UUID().uuidString)",
            baseURL: #require(URL(string: "https://bounds.example.com"))
        )
        let padID = "pad-\(UUID().uuidString)"
        // 400 events of 100 KB: ~40 MB of messages, against an 8 MB cap. Under the
        // flat charge this measured 80 KB and was cached.
        let heavy = (0 ..< 400).map { _ in event(message: String(repeating: "m", count: 100_000)) }

        store.set(padID, client: client, events: heavy, environments: [])

        #expect(store.get(padID, client: client) == nil)
    }

    @Test func `environment metadata alone can exceed cache admission`() throws {
        let client = CoderPadClient.mock(key: "metadata-budget-\(UUID().uuidString)")
        let data = try JSONSerialization.data(withJSONObject: [
            "id": 1, "file_contents": [["path": String(repeating: "p", count: 8_000_001)]]
        ])
        let environment = try CoderPadClient.decoder.decode(PadEnvironment.self, from: data)
        PadDetailCacheStore.shared.set("ABC123", client: client, events: [], environments: [environment])
        #expect(PadDetailCacheStore.shared.get("ABC123", client: client) == nil)
    }

    @Test func `history metadata participates in cache admission`() {
        let client = CoderPadClient.mock(key: "history-metadata-budget-\(UUID().uuidString)")
        let history = PadFileHistory(id: "f", title: String(repeating: "t", count: 8_000_001),
                                     language: nil, history: PadHistory())
        PadDetailCacheStore.shared.set("ABC123", client: client, events: [], environments: [], histories: [history])
        #expect(PadDetailCacheStore.shared.get("ABC123", client: client) == nil)
    }

    @Test func `an ordinary event log is still cached`() throws {
        let store = PadDetailCacheStore.shared
        let client = try CoderPadClient.live(
            apiKey: "key-\(UUID().uuidString)",
            baseURL: #require(URL(string: "https://bounds.example.com"))
        )
        let padID = "pad-\(UUID().uuidString)"
        let ordinary = (0 ..< 50).map { event(message: "Ran python (\($0))") }

        store.set(padID, client: client, events: ordinary, environments: [])

        #expect(store.get(padID, client: client)?.events.count == 50)
    }

    /// The third spelling `normalized(_:)` names but never handled: an explicit
    /// default port left a pad's events and environments resident under a second
    /// identity that teardown never retired (#4804).
    @Test func `an explicit default port shares the canonical identity`() throws {
        let key = "secret"
        let canonical = try PadDetailCacheStore.ClientIdentity(
            baseURL: #require(URL(string: "https://app.coderpad.io")), apiKey: key
        )
        let explicit = try PadDetailCacheStore.ClientIdentity(
            baseURL: #require(URL(string: "https://app.coderpad.io:443")), apiKey: key
        )

        #expect(explicit == canonical)
    }

    @Test func `an explicit http default port shares the canonical identity`() throws {
        let key = "secret"
        let canonical = try PadDetailCacheStore.ClientIdentity(
            baseURL: #require(URL(string: "http://local.example.com")), apiKey: key
        )
        let explicit = try PadDetailCacheStore.ClientIdentity(
            baseURL: #require(URL(string: "http://local.example.com:80")), apiKey: key
        )

        #expect(explicit == canonical)
    }

    /// A non-default port still identifies a different server.
    @Test func `a non-default port is still a distinct identity`() throws {
        let key = "secret"
        let canonical = try PadDetailCacheStore.ClientIdentity(
            baseURL: #require(URL(string: "https://self-hosted.example.com")), apiKey: key
        )
        let ported = try PadDetailCacheStore.ClientIdentity(
            baseURL: #require(URL(string: "https://self-hosted.example.com:8443")), apiKey: key
        )

        #expect(ported != canonical)
    }
}
