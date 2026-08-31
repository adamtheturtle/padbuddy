//
//  PadBuddyTests+BackgroundRefresh.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Background refresh snapshots")
@MainActor
struct BackgroundRefreshSnapshotTests {
    @Test func `health checks reject whitespace-only credentials`() {
        let blank = Account(name: "Blank", apiKey: " \n\t ", userEmail: "owner@example.com")
        let padded = Account(name: "Padded", apiKey: "  live-key\n", userEmail: "owner@example.com")

        #expect(AccountHealthMonitor.healthCheckAPIKey(for: blank) == nil)
        #expect(AccountHealthMonitor.healthCheckAPIKey(for: padded) == "live-key")
        #expect(AccountHealthMonitor.healthCheckAPIKey(for: Account.demo()) == nil)
        #expect(AccountHealthMonitor.healthCheckAPIKey(for: Account.demoBadKey()) == Account.badKeyMockKey)
    }

    @Test func `health checks start with bounded concurrency and replenish one at a time`() throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let jobs = (0 ..< 5).map { index in
            AccountHealthMonitor.CheckJob(
                accountID: UUID(),
                apiKey: "key-\(index)",
                baseURL: baseURL,
                isUnauthorizedMock: false
            )
        }
        var queue = AccountHealthMonitor.CheckQueue(jobs: jobs)

        let initial = queue.takeInitial()
        #expect(initial.map(\.apiKey) == ["key-0", "key-1", "key-2"])
        #expect(queue.takeNext()?.apiKey == "key-3")
        #expect(queue.takeNext()?.apiKey == "key-4")
        #expect(queue.takeNext() == nil)
    }

    @Test func `retry requested during a sweep runs immediately after it`() {
        var gate = PadsBackgroundRefresher.SweepGate()

        let started = gate.begin()
        let queued = gate.begin()
        #expect(started)
        #expect(!queued)
        #expect(gate.isInFlight)
        #expect(gate.hasPendingRequest)
        let continued = gate.finish()
        #expect(continued)
        #expect(gate.isInFlight)
        #expect(!gate.hasPendingRequest)
        let finished = gate.finish()
        #expect(!finished)
        #expect(!gate.isInFlight)
    }

    @Test func `multiple retry requests collapse into one follow-up sweep`() {
        var gate = PadsBackgroundRefresher.SweepGate()

        let started = gate.begin()
        let firstRetry = gate.begin()
        let secondRetry = gate.begin()
        let continued = gate.finish()
        let finished = gate.finish()

        #expect(started)
        #expect(!firstRetry)
        #expect(!secondRetry)
        #expect(continued)
        #expect(!finished)
    }

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
