import Foundation
@testable import PadBuddy
import Testing

@Suite("Bounded question title sort keys")
struct QuestionTitleSortBoundsTests {
    @Test func `oversized equal title prefixes use stable question identity ties`() throws {
        let prefix = String(repeating: "x", count: 500)
        let records: [[String: Any]] = [["id": 1, "title": prefix + "z"], ["id": 2, "title": prefix + "a"]]
        let questions = try CoderPadClient.decoder.decode(
            [Question].self, from: JSONSerialization.data(withJSONObject: records)
        )
        #expect(QuestionSort.titleAsc.sorted(questions).map(\.id) == [1, 2])
        #expect(QuestionSort.titleDesc.sorted(questions).map(\.id) == [1, 2])
    }
}
