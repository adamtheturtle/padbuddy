@testable import PadBuddy
import Testing

@Suite("Merged account task identity")
@MainActor
struct MergedAccountTokenTests {
    @Test
    func `credential changes alter a nonsecret token`() {
        var account = Account(name: "Acme", apiKey: "first-secret", userEmail: "owner@example.com")
        let first = MergedAccountToken(account: account)
        account.apiKey = "second-secret"
        let second = MergedAccountToken(account: account)

        #expect(first != second)
        #expect(!String(reflecting: first).contains("first-secret"))
    }

    @Test
    func `screen credential changes alter a nonsecret token`() {
        var account = Account(
            name: "Acme",
            apiKey: "interview",
            userEmail: "owner@example.com",
            screenApiKey: "first-screen-secret"
        )
        let first = MergedScreenAccountToken(account: account)
        account.screenApiKey = "second-screen-secret"
        let second = MergedScreenAccountToken(account: account)

        #expect(first != second)
        #expect(!String(reflecting: first).contains("first-screen-secret"))
    }
}
