import Foundation
@testable import PadBuddy
import Testing

@Suite("Screen safe links")
struct ScreenSafeLinksTests {
    @Test func `cleartext recruiter links fall back to HTTPS and cleartext only sessions have no link`() throws {
        let session = try ScreenTestSession(id: 1, url: "http://a.example/review",
                                            testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://b.example/take")
        #expect(try ScreenTestSession(id: 1, testURL: "http://b.example/take").screenURL == nil)
    }

    @Test func `oversized recruiter links do not prevent a bounded fallback`() throws {
        let session = try ScreenTestSession(id: 1, url: "https://a.example/" + String(repeating: "x", count: 10000),
                                            testURL: "https://b.example/take")
        #expect(session.screenURL?.absoluteString == "https://b.example/take")
    }
}
