import Foundation
@testable import PadBuddy
import Testing

@Suite("Question database presentation")
struct QuestionDatabasePresentationTests {
    @Test func `structured schemas bound tables columns and remote labels`() throws {
        let raw = "Remote\n\u{202E}" + String(repeating: "x", count: 500)
        let column: [String: Any] = ["name": raw, "type": raw, "pk": false, "nn": true]
        let table: [String: Any] = ["name": raw, "columns": Array(repeating: column, count: 40)]
        let data = try JSONSerialization.data(withJSONObject: [
            "id": 1, "title": raw, "description": raw, "language": raw,
            "schema_json": ["arrangement": Array(repeating: table, count: 40)]
        ])
        let database = try JSONDecoder().decode(QuestionCustomDatabase.self, from: data)
        let preview = QuestionDatabasePresentation(database)
        #expect(preview.tables.count == 16)
        #expect(preview.omittedTables == 24)
        #expect(preview.tables.allSatisfy { $0.columns.count == 32 && $0.omittedColumns == 8 })
        #expect(preview.tables.allSatisfy { $0.name.unicodeScalars.count <= 120 })
        #expect(preview.tables.flatMap(\.columns).allSatisfy {
            $0.name.unicodeScalars.count <= 120 && $0.type.unicodeScalars.count <= 80
        })
        #expect(!preview.title.contains("\u{202E}"))
        #expect(!preview.language.contains("\n"))
    }

    @Test func `fallback schema text is a bounded explicitly truncated preview`() throws {
        let schema = String(repeating: "x", count: 100_000)
        let data = try JSONSerialization.data(withJSONObject: ["id": 1, "schema": schema])
        let database = try JSONDecoder().decode(QuestionCustomDatabase.self, from: data)
        let preview = QuestionDatabasePresentation(database)
        #expect(preview.schema?.text.unicodeScalars.count == 16385)
        #expect(preview.schema?.isTruncated == true)
    }
}
