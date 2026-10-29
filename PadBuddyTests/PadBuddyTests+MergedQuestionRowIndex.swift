import Foundation
@testable import PadBuddy
import Testing

@Suite("Merged question row offset lookup")
@MainActor
struct MergedQuestionRowIndexTests {
    @Test func `selection resolves canonical rows after reordering and deletion`() throws {
        let questions = try CoderPadClient.decoder.decode([Question].self, from: Data(
            #"[{"id":1,"title":"First"},{"id":2,"title":"Second"}]"#.utf8
        ))
        let account = Account(name: "Account", apiKey: "")
        let rows = questions.map { MergedQuestionRow(account: account, item: $0) }
        let cache = ScopedQuestionsCache()
        cache.rows = rows
        #expect(cache.row(forID: rows[0].id)?.item.title == "First")
        cache.rows = Array(rows.reversed())
        #expect(cache.row(forID: rows[0].id)?.item.title == "First")
        cache.rows = [rows[1]]
        #expect(cache.row(forID: rows[0].id) == nil)
        #expect(cache.row(forID: rows[1].id)?.item.title == "Second")
    }
}
