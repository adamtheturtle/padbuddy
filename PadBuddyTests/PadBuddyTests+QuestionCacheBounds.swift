import Foundation
@testable import PadBuddy
import Testing

@Suite("Question cache snapshot bounds")
@MainActor
struct QuestionCacheBoundsTests {
    @Test func `oversized question arrays are rejected before decoding malformed records`() throws {
        let records = Array(repeating: "{}", count: CacheRecordLimit.maximumElements + 1)
        let json = "[" + records.joined(separator: ",") + "]"
        do {
            _ = try JSONDecoder().decode(
                BoundedDecodedArray<Question, CacheRecordLimit>.self, from: Data(json.utf8)
            )
            Issue.record("Oversized snapshot was accepted")
        } catch DecodingError.dataCorrupted {
            // A model decode would fail with keyNotFound; the count guard runs first.
        }
    }

    @Test func `ordinary question cache arrays retain their existing representation`() throws {
        let data = Data(#"[{"id":42,"title":"Question"}]"#.utf8)
        let snapshot = try JSONDecoder().decode(BoundedDecodedArray<Question, CacheRecordLimit>.self, from: data)
        #expect(snapshot.values.map(\.id) == [42])
    }
}
