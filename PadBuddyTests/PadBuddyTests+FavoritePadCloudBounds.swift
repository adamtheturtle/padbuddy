import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite pad cloud input bounds")
@MainActor
struct FavoritePadCloudBoundsTests {
    @Test func `mirror bytes accounts and per account records are bounded`() throws {
        #expect(FavoritePadsStore.decodeCloudFavorites(Data(repeating: 0x20, count: 1_048_577)) == nil)
        let accounts = Dictionary(uniqueKeysWithValues: (0 ... 256).map { ("account\($0)", [FavoritePad]()) })
        #expect(try FavoritePadsStore.decodeCloudFavorites(JSONEncoder().encode(accounts)) == nil)
        let entry = FavoritePad(id: "pad123", title: "Title")
        let object = ["account": Array(repeating: entry, count: 501)]
        #expect(try FavoritePadsStore.decodeCloudFavorites(JSONEncoder().encode(object)) == nil)
        let accepted = try FavoritePadsStore.decodeCloudFavorites(JSONEncoder().encode(["account": [entry]]))
        #expect(accepted?["account"] == [entry])
    }

    @Test func `oversized favorite fields are rejected before merging`() throws {
        for entry in [FavoritePad(id: String(repeating: "a", count: 257), title: "Title"),
                      FavoritePad(id: "pad123", title: String(repeating: "a", count: 4097))] {
            #expect(try FavoritePadsStore.decodeCloudFavorites(JSONEncoder().encode(["account": [entry]])) == nil)
        }
    }

    @Test func `tombstones enforce record and identifier budgets`() throws {
        let entries = Dictionary(uniqueKeysWithValues: (0 ... 500).map { ("pad\($0)", Date()) })
        #expect(try FavoritePadsStore.decodeCloudTombstones(JSONEncoder().encode(["account": entries])) == nil)
        let longKey = ["account": [String(repeating: "a", count: 257): Date()]]
        #expect(try FavoritePadsStore.decodeCloudTombstones(JSONEncoder().encode(longKey)) == nil)
    }
}
