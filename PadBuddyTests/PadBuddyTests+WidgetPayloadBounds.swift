import Foundation
@testable import PadBuddy
import Testing

@Suite("Widget payload bounds")
struct WidgetPayloadBoundsTests {
    @Test func `newest selection keeps deterministic ties without sorting the complete cache`() throws {
        let records = (0 ..< 1000).reversed().map { ["id": String(format: "p%04d", $0), "title": "Pad"] }
        let pads = try CoderPadClient.decoder.decode([Pad].self, from: JSONSerialization.data(withJSONObject: records))
        #expect(WidgetSync.recentSnapshots(from: pads).map(\.id) == (0 ..< 8).map { String(format: "p%04d", $0) })
    }

    @Test func `duplicate snapshot identities retain the newest occurrence`() throws {
        let records = [
            ["id": "same", "title": "Older", "updated_at": "2026-01-01T00:00:00Z"],
            ["id": "same", "title": "Newer", "updated_at": "2026-02-01T00:00:00Z"]
        ]
        let pads = try CoderPadClient.decoder.decode([Pad].self, from: JSONSerialization.data(withJSONObject: records))
        #expect(WidgetSync.recentSnapshots(from: pads).map(\.title) == ["Newer"])
    }

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
