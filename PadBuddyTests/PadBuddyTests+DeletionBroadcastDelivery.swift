//
//  PadBuddyTests+DeletionBroadcastDelivery.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Deletion broadcast delivery (#4595)")
@MainActor
struct DeletionBroadcastDeliveryTests {
    /// 64 was the bounded buffer that silently dropped the oldest events, leaving their
    /// disk cache, favorites, Spotlight entries, and open history behind forever.
    private let burst = 200

    /// Collects up to `count` values, giving up after `timeout` so a dropped broadcast
    /// fails the test rather than hanging it.
    private func collect<T: Sendable>(
        _ stream: AsyncStream<T>, count: Int, timeout: Duration = .seconds(10)
    ) async -> [T] {
        await withTaskGroup(of: [T]?.self) { group in
            group.addTask {
                var received: [T] = []
                for await value in stream {
                    received.append(value)
                    guard received.count < count else { break }
                }
                return received
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap(\.self) ?? []
        }
    }

    @Test func `a burst larger than the update buffer delivers every pad deletion`() async {
        let stream = AppRouter.padDeletions
        let account = UUID()
        for index in 0 ..< burst {
            AppRouter.padDeleted(id: "pad-\(index)", account: account, via: CoderPadClient(apiKey: "key"))
        }

        let received = await collect(stream, count: burst).map(\.id)

        #expect(received == (0 ..< burst).map { "pad-\($0)" })
    }

    @Test func `a burst larger than the update buffer delivers every question deletion`() async {
        let stream = AppRouter.questionDeletions
        let account = UUID()
        for index in 0 ..< burst {
            AppRouter.questionDeleted(id: index, account: account, via: CoderPadClient(apiKey: "key"))
        }

        let received = await collect(stream, count: burst).map(\.id)

        #expect(received == Array(0 ..< burst))
    }
}
