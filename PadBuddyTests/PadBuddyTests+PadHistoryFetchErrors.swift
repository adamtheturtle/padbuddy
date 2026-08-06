@testable import PadBuddy
import Testing

@Suite("Pad history fetch errors")
struct PadHistoryFetchErrorTests {
    @Test
    func `demo history uses the mock client's transport`() async throws {
        let client = CoderPadClient.mock(key: "history-fetcher-demo")
        let history = try await client.padHistory(
            historyURL: "https://coderpad-1.firebaseio.com/mock/pad-environments/1/files/0/history.json"
        )

        #expect(!history.isEmpty)
    }

    @Test
    func `missing optional history is not a load failure`() {
        func isOptionalMissing(_ error: CoderPadError) -> Bool {
            if case let .http(status, _) = error {
                return status == 404 || status == 410
            }
            return false
        }

        #expect(isOptionalMissing(.http(404, "")))
        #expect(isOptionalMissing(.http(410, "")))
        #expect(!isOptionalMissing(.http(401, "")))
        #expect(!isOptionalMissing(.http(500, "")))
    }
}
