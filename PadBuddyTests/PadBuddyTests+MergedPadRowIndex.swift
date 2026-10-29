import Foundation
@testable import PadBuddy
import Testing

@Suite("Merged pad row offset lookup")
@MainActor
struct MergedPadRowIndexTests {
    @Test func `selection resolves canonical rows after reordering and deletion`() throws {
        let pads = try CoderPadClient.decoder.decode([Pad].self, from: Data(
            #"[{"id":"first","title":"First"},{"id":"second","title":"Second"}]"#.utf8
        ))
        let account = Account(name: "Account", apiKey: "")
        let rows = pads.map { AccountScoped(account: account, item: $0, id: $0.id) }
        let cache = ScopedPadsCache()
        cache.rows = rows
        #expect(cache.row(forID: "first")?.item.title == "First")
        cache.rows = Array(rows.reversed())
        #expect(cache.row(forID: "first")?.item.title == "First")
        cache.rows = [rows[1]]
        #expect(cache.row(forID: "first")?.item.id == nil)
        #expect(cache.row(forID: "second")?.item.title == "Second")
    }
}
