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
    /// UI delivery is bounded; persistent cleanup has separate durable coverage.
    private let burst = 64

    /// The test deadline cancels iteration if a broadcast is dropped. Match only this
    /// test's account so concurrent deletion tests cannot satisfy its event count.
    private func collect<T: Sendable>(
        _ stream: AsyncStream<T>, count: Int, matching predicate: (T) -> Bool
    ) async -> [T] {
        var received: [T] = []
        for await value in stream where predicate(value) {
            received.append(value)
            guard received.count < count else { break }
        }
        return received
    }

    @Test(.timeLimit(.minutes(1)))
    func `a burst within the UI buffer delivers every pad deletion`() async {
        let stream = AppRouter.padDeletions
        let account = UUID()
        for index in 0 ..< burst {
            AppRouter.padDeleted(id: "pad-\(index)", account: account, via: CoderPadClient(apiKey: "key"))
        }

        let received = await collect(stream, count: burst, matching: { $0.account == account }).map(\.id)

        #expect(received == (0 ..< burst).map { "pad-\($0)" })
    }

    @Test(.timeLimit(.minutes(1)))
    func `a burst within the UI buffer delivers every question deletion`() async {
        let stream = AppRouter.questionDeletions
        let account = UUID()
        for index in 0 ..< burst {
            AppRouter.questionDeleted(id: index, account: account, via: CoderPadClient(apiKey: "key"))
        }

        let received = await collect(stream, count: burst, matching: { $0.account == account }).map(\.id)

        #expect(received == Array(0 ..< burst))
    }
}
