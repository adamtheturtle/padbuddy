import Foundation
@testable import PadBuddy
import Testing

@Suite("Deep link host case normalization")
struct DeepLinkHostCaseTests {
    @Test(arguments: ["pad", "PAD", "PaD"])
    func `pad hosts are case insensitive in both supported schemes`(_ host: String) throws {
        for scheme in ["coderpad", "com.adamdangoor.padbuddy"] {
            let url = try #require(URL(string: "\(scheme)://\(host)/abc-123_"))
            #expect(PadBuddyApp.padID(fromDeepLink: url) == "abc-123_")
        }
    }
}
