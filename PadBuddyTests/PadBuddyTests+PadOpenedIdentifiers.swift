import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad-open identifier sanitization")
struct PadOpenedIdentifierTests {
    @Test(arguments: ["abc/def", "abc\nx", "a?b", String(repeating: "x", count: 65)])
    func `unroutable identifiers cannot enter durable open history`(_ raw: String) {
        #expect(PadOpenedStore.normalizedRecordID(raw) == nil)
    }

    @Test func `restored records normalize before deduplication and keep the latest valid open`() {
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let records = PadOpenedStore.normalizedRecordIDs([
            " abc-123_ ": earlier, "abc-123_": later, "../invalid": later,
            String(repeating: "x", count: 1_000_000): later
        ])
        #expect(records == ["abc-123_": later])
    }
}
