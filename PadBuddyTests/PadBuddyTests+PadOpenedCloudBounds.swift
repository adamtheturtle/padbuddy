import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad-open cloud input bounds")
@MainActor
struct PadOpenedCloudBoundsTests {
    @Test func `cloud history rejects excessive raw bytes accounts records and keys`() throws {
        #expect(PadOpenedStore.decodeCloudHistory(Data(repeating: 0x20, count: 1_048_577)) == nil)
        let accounts = Dictionary(uniqueKeysWithValues: (0 ... 256).map { ("account\($0)", [String: Date]()) })
        #expect(try PadOpenedStore.decodeCloudHistory(JSONEncoder().encode(accounts)) == nil)
        let entries = Dictionary(uniqueKeysWithValues: (0 ... 500).map { ("pad\($0)", Date()) })
        #expect(try PadOpenedStore.decodeCloudHistory(JSONEncoder().encode(["account": entries])) == nil)
        let longKey = ["account": [String(repeating: "a", count: 257): Date()]]
        #expect(try PadOpenedStore.decodeCloudHistory(JSONEncoder().encode(longKey)) == nil)
    }

    @Test func `cloud identifiers are normalized before history or tombstone merges`() throws {
        let old = Date(timeIntervalSinceReferenceDate: 1)
        let new = Date(timeIntervalSinceReferenceDate: 2)
        let entries = ["account": [" pad123 ": old, "pad123": new, "invalid/id": new]]
        let decoded = try PadOpenedStore.decodeCloudHistory(JSONEncoder().encode(entries))
        #expect(decoded?["account"] == ["pad123": new])
    }
}
