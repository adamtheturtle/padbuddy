@testable import CoderPad
import Testing

@Suite("Pad history fetch errors")
struct PadHistoryFetchErrorTests {
    @Test
    func `missing optional history is not a load failure`() {
        #expect(PadHistoryFetcher.FetchError.httpStatus(404).isOptionalMissingHistory)
        #expect(PadHistoryFetcher.FetchError.httpStatus(410).isOptionalMissingHistory)
        #expect(!PadHistoryFetcher.FetchError.httpStatus(401).isOptionalMissingHistory)
        #expect(!PadHistoryFetcher.FetchError.httpStatus(500).isOptionalMissingHistory)
    }
}
