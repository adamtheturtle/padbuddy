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

        cloud = try #require(FavoritePadsStore.removingCloudAccount("removed", from: cloud))
        let roundTrip = try SharedCoders.decoder.decode(
            [String: [FavoritePad]].self,
            from: SharedCoders.encoder.encode(cloud)
        )

        #expect(roundTrip["removed"] == nil)
        #expect(roundTrip["kept"]?.map(\.id) == ["pad-b"])
    }
}
