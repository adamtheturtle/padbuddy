@testable import PadBuddy
import Testing

@Suite("Account section header privacy")
struct AccountSectionHeaderPrivacyTests {
    @Test
    func `email is hidden by default even when it is the only identity`() {
        let account = Account(name: "  ", apiKey: "key", userEmail: "owner@example.com")

        let identity = AccountSectionHeaderIdentity(account: account, showEmail: false)

        #expect(identity.displayName == "Account")
        #expect(identity.email == nil)
    }

    @Test
    func `explicit reveal shows email without duplicating it`() {
        let named = Account(name: "Acme", apiKey: "key", userEmail: "owner@example.com")
        let unnamed = Account(name: "", apiKey: "key", userEmail: "owner@example.com")

        #expect(AccountSectionHeaderIdentity(account: named, showEmail: true).email == "owner@example.com")
        #expect(AccountSectionHeaderIdentity(account: unnamed, showEmail: true).displayName == "owner@example.com")
        #expect(AccountSectionHeaderIdentity(account: unnamed, showEmail: true).email == nil)
    }
}
