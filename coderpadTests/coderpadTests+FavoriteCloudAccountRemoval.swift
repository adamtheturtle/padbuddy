@testable import CoderPad
import Foundation
import Testing

@Suite("Favorite cloud account removal")
struct FavoriteCloudAccountRemovalTests {
    @Test
    func `removing one sync identity preserves other cloud accounts`() throws {
        var cloud = [
            "removed": [FavoritePad(id: "pad-a", title: "A", addedAt: nil)],
            "kept": [FavoritePad(id: "pad-b", title: "B", addedAt: nil)]
        ]

        cloud = try #require(CloudSyncMerge.removingAccount("removed", from: cloud))
        let roundTrip = try SharedCoders.decoder.decode(
            [String: [FavoritePad]].self,
            from: SharedCoders.encoder.encode(cloud)
        )

        #expect(roundTrip["removed"] == nil)
        #expect(roundTrip["kept"]?.map(\.id) == ["pad-b"])
    }

    @Test
    func `question cloud cleanup removes membership and tombstone account maps`() throws {
        let questions = [
            "removed": [FavoriteQuestion(id: 1, title: "A", addedAt: nil)],
            "kept": [FavoriteQuestion(id: 2, title: "B", addedAt: nil)]
        ]
        let tombstones = ["removed": ["1": Date()], "kept": ["3": Date()]]

        let cleanedQuestions = try #require(CloudSyncMerge.removingAccount("removed", from: questions))
        let cleanedTombstones = try #require(CloudSyncMerge.removingAccount("removed", from: tombstones))

        #expect(cleanedQuestions["removed"] == nil)
        #expect(cleanedQuestions["kept"]?.map(\.id) == [2])
        #expect(cleanedTombstones["removed"] == nil)
        #expect(cleanedTombstones["kept"]?["3"] != nil)
    }
}
