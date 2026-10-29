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

    @Test func `widget links resolve stable and legacy account identities`() throws {
        let account = Account(name: "Example", apiKey: "")
        let stable = WidgetAccountIdentity.identifier(for: account)
        for identity in [stable, stable.uppercased(), account.id.uuidString.lowercased()] {
            let url = try #require(URL(string: "coderpad://pad/example?account=\(identity)"))
            #expect(try PadBuddyApp.validatedAccountID(fromDeepLink: url, availableAccounts: [account]) == account.id)
        }
        let invalidQueries = [
            "account", "account=", "account=invalid", "account=\(UUID())", "account=\(stable)&account=\(stable)"
        ]
        for query in invalidQueries {
            let url = try #require(URL(string: "coderpad://pads?\(query)"))
            #expect(throws: PadBuddyApp.DeepLinkAccountError.self) {
                try PadBuddyApp.validatedAccountID(fromDeepLink: url, availableAccounts: [account])
            }
        }
        let removed = try #require(URL(string: "coderpad://pads?account=\(stable)"))
        #expect(throws: PadBuddyApp.DeepLinkAccountError.self) {
            try PadBuddyApp.validatedAccountID(fromDeepLink: removed, availableAccounts: [])
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
