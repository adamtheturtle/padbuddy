import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite future timestamp policy")
struct FavoriteFutureTimestampTests {
    @Test func `mutation stamps ignore implausibly future observations but preserve normal skew`() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(CloudTombstones.nextTimestamp(observing: [.distantFuture], now: now)
            == now.addingTimeInterval(0.001))
        let skewed = now.addingTimeInterval(60)
        #expect(CloudTombstones.nextTimestamp(observing: [skewed], now: now)
            == skewed.addingTimeInterval(0.001))
        #expect(FutureTimestampPolicy.clamped(.distantFuture, now: now) == now)
        #expect(FutureTimestampPolicy.clamped(skewed, now: now) == skewed)
    }

    @Test func `favorite restoration clamps addition and removal dates before reconciliation`() throws {
        let before = Date()
        let pads = FavoritePadsStore.sanitized([FavoritePad(id: "abc123", title: "Pad", addedAt: .distantFuture)])
        let questions = FavoriteQuestionsStore.sanitized([
            FavoriteQuestion(id: 42, title: "Question", addedAt: .distantFuture)
        ])
        let tombstones = CloudTombstoneClamp.clamped(["abc123": Date.distantFuture], limit: 500)
        let dates = try [#require(pads.first?.addedAt), #require(questions.first?.addedAt),
                         #require(tombstones["abc123"])]
        #expect(dates.allSatisfy { $0 >= before && $0 <= Date() })
    }
}
