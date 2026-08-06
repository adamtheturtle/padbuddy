//
//  PadBuddyTests+BackgroundRefresh.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Background refresh snapshots")
@MainActor
struct BackgroundRefreshSnapshotTests {
    @Test func `identical pad results do not rewrite the cache`() {
        let pads = [Pad(id: "one", title: "One"), Pad(id: "two", title: "Two")]
        #expect(!PadsBackgroundRefresher.cacheNeedsUpdate(cached: pads, fetched: pads))
    }

    @Test func `content order and membership changes rewrite the cache`() {
        let one = Pad(id: "one", title: "One")
        let two = Pad(id: "two", title: "Two")
        #expect(PadsBackgroundRefresher.cacheNeedsUpdate(cached: [one, two], fetched: [two, one]))
        #expect(PadsBackgroundRefresher.cacheNeedsUpdate(cached: [one], fetched: [one, two]))
        #expect(PadsBackgroundRefresher.cacheNeedsUpdate(
            cached: [one], fetched: [Pad(id: "one", title: "Renamed")]
        ))
    }

    @Test
    func `a changed backend reseeds instead of returning its old snapshot`() {
        let accountID = UUID()
        let firstClient = ClientTaskIdentity(apiKey: "first", baseURL: URL.staticURL("https://example.com"))
        let secondClient = ClientTaskIdentity(apiKey: "second", baseURL: URL.staticURL("https://example.com"))
        let first = ["old": PadActivitySnapshot(updatedAt: nil, isEnded: false, participantCount: 1)]
        let second = ["new": PadActivitySnapshot(updatedAt: nil, isEnded: false, participantCount: 2)]
        var states: [UUID: PadsBackgroundRefresher.AccountActivityState] = [:]

        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: firstClient, snapshot: first, states: &states
        ) == nil)
        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: firstClient, snapshot: second, states: &states
        )?["old"]?.participantCount == 1)
        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: secondClient, snapshot: first, states: &states
        ) == nil)
        #expect(PadsBackgroundRefresher.replaceSnapshot(
            accountID: accountID, clientIdentity: secondClient, snapshot: second, states: &states
        )?["old"]?.participantCount == 1)
    }

    @Test
    func `refresh failure backoff grows and caps`() {
        #expect(PadsBackgroundRefresher.retryDelay(for: 1) == 300)
        #expect(PadsBackgroundRefresher.retryDelay(for: 3) == 1200)
        #expect(PadsBackgroundRefresher.retryDelay(for: 20) == 3600)
    }

    @Test
    func `refresh errors are categorized without retaining response details`() {
        #expect(PadsBackgroundRefresher.failureKind(for: CoderPadError.http(401, "secret")) == .unauthorized)
        #expect(PadsBackgroundRefresher.failureKind(for: CoderPadError.http(503, "secret")) == .server)
        #expect(PadsBackgroundRefresher.failureKind(for: CoderPadError.decode("secret")) == .invalidResponse)
        #expect(PadsBackgroundRefresher.failureKind(for: URLError(.notConnectedToInternet)) == .network)
    }
}
