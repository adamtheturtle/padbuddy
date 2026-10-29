import Foundation
@testable import PadBuddy
import Testing

@Suite("System Focus account usability")
@MainActor
struct FocusSystemAccountTests {
    @Test func `system state rejects accounts that lost credentials or have malformed servers`() {
        let missingKey = Account(name: "Missing key", apiKey: "")
        let malformed = Account(name: "Bad URL", apiKey: "key", baseURL: "https://[")
        for account in [missingKey, malformed] {
            #expect(ScopeToAccountFocusFilter.usableSystemAccountID(
                account.id.uuidString, accounts: [account]
            ) == nil)
        }
    }

    @Test func `system state preserves usable and mock accounts and rejects removed ones`() {
        let normal = Account(name: "Account", apiKey: "key")
        let mock = Account.demo()
        for account in [normal, mock] {
            #expect(ScopeToAccountFocusFilter.usableSystemAccountID(
                AccountFocusIdentity.identifier(for: account), accounts: [account]
            ) == account.id)
            #expect(ScopeToAccountFocusFilter.usableSystemAccountID(
                AccountFocusIdentity.identifier(for: account), accounts: []
            ) == nil)
        }
    }
}
