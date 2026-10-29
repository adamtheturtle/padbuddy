import Foundation
@testable import PadBuddy
import Testing

struct ScreenPageSliceTests {
    @Test func `paging preserves the server cursor and rejects a repeated offset`() throws {
        let json = #"{"tests":[],"pagination":{"start":0,"limit":50,"has_more_items":true,"next_start":50}}"#
        let page = try CoderPadClient.decoder.decode(ScreenTestsPage.self, from: Data(json.utf8))
        #expect(try ScreenTestPageSlice(page: page, requestedStart: 0).nextStart == 50)
        #expect(throws: CoderPadError.self) { try ScreenTestPageSlice(page: page, requestedStart: 50) }
    }

    @Test func `a server ignoring the requested page limit cannot publish an oversized page`() throws {
        let tests = (1 ... 51).map { ["id": $0, "status": "waiting"] as [String: Any] }
        let data = try JSONSerialization.data(withJSONObject: ["tests": tests])
        let page = try CoderPadClient.decoder.decode(ScreenTestsPage.self, from: data)
        #expect(throws: CoderPadError.self) { try ScreenTestPageSlice(page: page, requestedStart: 0) }
    }
}
