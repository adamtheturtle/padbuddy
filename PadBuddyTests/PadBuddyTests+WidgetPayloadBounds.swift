import Foundation
@testable import PadBuddy
import Testing

@Suite("Widget payload bounds")
struct WidgetPayloadBoundsTests {
    @Test func `account indexes remain readable with oversized names and account lists`() throws {
        let name = String(repeating: "😀", count: 100_000)
        let accounts = (0 ..< WidgetSync.maximumIndexedAccounts + 10).map { _ in Account(name: name, apiKey: "") }
        let index = WidgetSync.accountIndex(accounts)
        #expect(index.count == WidgetSync.maximumIndexedAccounts)
        #expect(index.allSatisfy { $0.name.unicodeScalars.count <= 128 })
        #expect(try JSONEncoder().encode(index).count < WidgetSharedStore.maxSnapshotFileBytes)
    }
}
