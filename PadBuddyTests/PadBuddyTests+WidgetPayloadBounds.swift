import Foundation
@testable import PadBuddy
import Testing

@Suite("Widget payload bounds")
struct WidgetPayloadBoundsTests {
    @Test func `oversized remote pad metadata produces a readable bounded snapshot`() throws {
        let json: [String: String] = [
            "id": "abc123", "title": String(repeating: "😀", count: 100_000),
            "language": String(repeating: "x", count: 100_000)
        ]
        let pad = try JSONDecoder().decode(Pad.self, from: JSONSerialization.data(withJSONObject: json))
        let snapshots = WidgetSync.recentSnapshots(from: [pad])
        let snapshot = try #require(snapshots.first)
        #expect(snapshot.title.unicodeScalars.count <= 128)
        #expect((snapshot.language?.count ?? 0) <= 64)
        #expect(try JSONEncoder().encode(snapshots).count < WidgetSharedStore.maxSnapshotFileBytes)
    }

    @Test func `account indexes remain readable with oversized names and account lists`() throws {
        let name = String(repeating: "😀", count: 100_000)
        let accounts = (0 ..< WidgetSync.maximumIndexedAccounts + 10).map { _ in Account(name: name, apiKey: "") }
        let index = WidgetSync.accountIndex(accounts)
        #expect(index.count == WidgetSync.maximumIndexedAccounts)
        #expect(index.allSatisfy { $0.name.unicodeScalars.count <= 128 })
        #expect(try JSONEncoder().encode(index).count < WidgetSharedStore.maxSnapshotFileBytes)
    }
}
