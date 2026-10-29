import Foundation
@testable import PadBuddy
import Testing

@Suite("Deep link host case normalization")
struct DeepLinkHostCaseTests {
    @Test
    func `explicit account parameters must name one live account`() throws {
        let id = UUID()
        let valid = try #require(URL(string: "coderpad://pads?account=\(id.uuidString)"))
        #expect(try PadBuddyApp.validatedAccountID(fromDeepLink: valid, availableAccountIDs: [id]) == id)
        let accountless = try #require(URL(string: "coderpad://pads"))
        #expect(try PadBuddyApp.validatedAccountID(fromDeepLink: accountless, availableAccountIDs: [id]) == nil)
        for query in ["account", "account=", "account=invalid", "account=\(UUID())", "account=\(id)&account=\(id)"] {
            let url = try #require(URL(string: "coderpad://pads?\(query)"))
            #expect(throws: PadBuddyApp.DeepLinkAccountError.self) {
                try PadBuddyApp.validatedAccountID(fromDeepLink: url, availableAccountIDs: [id])
            }
        }
    }

    @Test(arguments: ["pad", "PAD", "PaD"])
    func `pad hosts are case insensitive in both supported schemes`(_ host: String) throws {
        for scheme in ["coderpad", "com.adamdangoor.padbuddy"] {
            let url = try #require(URL(string: "\(scheme)://\(host)/abc-123_"))
            #expect(PadBuddyApp.padID(fromDeepLink: url) == "abc-123_")
        }
    }
}
