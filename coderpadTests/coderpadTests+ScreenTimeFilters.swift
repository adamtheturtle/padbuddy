@testable import CoderPad
import Foundation
import Testing

@Suite("Screen time filters")
struct ScreenTimeFilterTests {
    @Test
    func `invalid ranges are rejected before transport`() async {
        let client = ScreenClient(apiKey: "key", session: URLSession(configuration: .ephemeral))
        let invalidRanges: [(from: Int?, until: Int?)] = [(-1, nil), (nil, -1), (2, 1)]

        for range in invalidRanges {
            do {
                _ = try await client.listTests(from: range.from, until: range.until)
                Issue.record("Expected an invalid Screen time filter to throw")
            } catch let error as CoderPadError {
                #expect(error.description.contains("time filter"))
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
