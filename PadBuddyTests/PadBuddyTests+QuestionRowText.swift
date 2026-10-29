import Foundation
@testable import PadBuddy
import Testing

@Suite("Question row text bounds")
struct QuestionRowTextTests {
    @Test func `oversized row titles and metadata remain bounded for display and accessibility`() throws {
        let json: [String: Any] = [
            "id": 42, "title": String(repeating: "😀", count: 100_000),
            "language": String(repeating: "x", count: 100_000)
        ]
        let question = try JSONDecoder().decode(Question.self, from: JSONSerialization.data(withJSONObject: json))
        let account = RowAccount(Account(name: String(repeating: "y", count: 100_000), apiKey: ""))
        let presentation = QuestionRowPresentation(question: question, account: account)
        #expect(presentation.title.unicodeScalars.count <= 200)
        #expect((presentation.languageDisplayName?.count ?? 0) <= 64)
        #expect(presentation.accessibilityLabel.unicodeScalars.count <= 400)
    }
}
