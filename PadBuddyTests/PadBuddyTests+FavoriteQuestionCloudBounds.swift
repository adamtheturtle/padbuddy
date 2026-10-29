import Foundation
@testable import PadBuddy
import Testing

@Suite("Favorite question cloud input bounds")
@MainActor
struct FavoriteQuestionCloudBoundsTests {
    @Test func `oversized bytes account sets and identity keys are rejected`() throws {
        let large = Data(repeating: 0x20, count: CloudSnapshotDecoder.maximumBytes + 1)
        #expect(FavoriteQuestionsStore.decodeCloudFavorites(large) == nil)
        let accounts = Dictionary(uniqueKeysWithValues: (0 ... 256).map { ("account\($0)", [Int]()) })
        #expect(try FavoriteQuestionsStore.decodeCloudFavorites(JSONEncoder().encode(accounts)) == nil)
        let key = String(repeating: "x", count: 4097)
        #expect(try FavoriteQuestionsStore.decodeCloudFavorites(JSONEncoder().encode([key: [Int]()])) == nil)
    }

    @Test func `per account record limits apply before favorite normalization`() throws {
        let entry = ["id": 42, "title": "Question"] as [String: Any]
        let object = ["account": Array(repeating: entry, count: FavoriteQuestionsStore.maxEntriesPerAccount + 1)]
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(FavoriteQuestionsStore.decodeCloudFavorites(data) == nil)
        let accepted = Data(#"{"account":[{"id":42,"title":"Question"}]}"#.utf8)
        #expect(FavoriteQuestionsStore.decodeCloudFavorites(accepted)?["account"]?.first?.id == 42)
    }

    @Test func `tombstone dictionaries share the input budgets`() throws {
        let entries = Dictionary(uniqueKeysWithValues: (0 ... FavoriteQuestionsStore.maxEntriesPerAccount).map {
            (String($0), Date(timeIntervalSinceReferenceDate: 0))
        })
        #expect(try FavoriteQuestionsStore.decodeCloudTombstones(JSONEncoder().encode(["account": entries])) == nil)
    }
}
