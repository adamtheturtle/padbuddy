import Foundation
@testable import PadBuddy
import Testing

@Suite("Restored companion credential validation")
struct CompanionCredentialValidationTests {
    @Test(arguments: ["   ", "key\u{0000}suffix", "key\u{200E}suffix", String(repeating: "k", count: 4097)])
    func `stored formats refuse api keys provisioning would reject`(key: String) throws {
        #expect(CompanionCredentials(encoded: Data("https://coderpad.io\n\(key)".utf8)) == nil)
        let server = try #require(URL(string: "https://coderpad.io"))
        #expect(CompanionCredentials.legacy(apiKeyData: Data(key.utf8), storedServer: server) == nil)
    }
}
