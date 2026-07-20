@testable import CoderPad
import Testing

@Suite("Pad history fetch errors")
struct PadHistoryFetchErrorTests {
    @Test
    func `demo history uses the mock client's transport`() async throws {
        let client = CoderPadClient.mock(key: "history-fetcher-demo")
        let history = try await PadHistoryFetcher.fetch(
            "https://coderpad-1.firebaseio.com/mock/pad-environments/1/files/0/history.json",
            client: client,
            usesMockTransport: true
        )

        #expect(!history.isEmpty)
    }

    @Test
    func `missing optional history is not a load failure`() {
        #expect(PadHistoryFetcher.FetchError.httpStatus(404).isOptionalMissingHistory)
        #expect(PadHistoryFetcher.FetchError.httpStatus(410).isOptionalMissingHistory)
        #expect(!PadHistoryFetcher.FetchError.httpStatus(401).isOptionalMissingHistory)
        #expect(!PadHistoryFetcher.FetchError.httpStatus(500).isOptionalMissingHistory)
    }
}
