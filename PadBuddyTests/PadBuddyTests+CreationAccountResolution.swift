import Foundation
@testable import PadBuddy
import Testing

@Suite("Creation account resolution")
struct CreationAccountResolutionTests {
    @Test func `creation account resolution preserves organization scope and availability`() {
        let missing = Account(name: "Missing", apiKey: " ")
        let live = Account(name: "Live", apiKey: "key")
        let accounts = [missing, live]
        #expect(AppCreationAvailability.creationAccount(
            accounts: accounts, currentAccountID: missing.id, isMergedView: false,
            requestedAccountID: nil, isOffline: false
        ) == nil)
        #expect(AppCreationAvailability.creationAccount(
            accounts: accounts, currentAccountID: live.id, isMergedView: true,
            requestedAccountID: missing.id, isOffline: false
        ) == nil)
        #expect(AppCreationAvailability.creationAccount(
            accounts: accounts, currentAccountID: live.id, isMergedView: false,
            requestedAccountID: nil, isOffline: true
        ) == nil)
        #expect(AppCreationAvailability.creationAccount(
            accounts: accounts, currentAccountID: missing.id, isMergedView: true,
            requestedAccountID: nil, isOffline: false
        )?.id == live.id)
    }
}
