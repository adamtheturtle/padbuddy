import Foundation
@testable import PadBuddy
import Testing

@Suite("Synced account snapshot bounds")
@MainActor
struct SyncedAccountBoundsTests {
    @Test func `excessive account counts are rejected before adoption`() throws {
        let accounts = (0 ... Keychain.maximumSyncedAccounts).map { Account(name: "Account \($0)", apiKey: "key") }
        #expect(try !Keychain.decodesToUsableAccounts(JSONEncoder().encode(accounts)))
    }

    @Test func `oversized fields and raw snapshots remain unusable`() throws {
        let longName = Account(name: String(repeating: "x", count: 513), apiKey: "key")
        #expect(try !Keychain.decodesToUsableAccounts(JSONEncoder().encode([longName])))
        let oversized = Account(
            name: "Account", apiKey: String(repeating: "x", count: Keychain.maximumSyncedAccountBytes)
        )
        let data = try JSONEncoder().encode([oversized])
        #expect(data.count > Keychain.maximumSyncedAccountBytes)
        #expect(!Keychain.decodesToUsableAccounts(data))
        #expect(Keychain.encodeSyncedAccountsSnapshot(accounts: data, revision: Data("1".utf8)) == nil)
    }

    @Test func `versioned envelopes reject oversized account and revision fields`() throws {
        let large = Keychain.SyncedAccountsSnapshot(
            accounts: Data(repeating: 0x41, count: Keychain.maximumSyncedAccountBytes + 1), revision: Data("1".utf8)
        )
        #expect(try Keychain.decodeSyncedAccountsSnapshot(JSONEncoder().encode(large)) == nil)
        #expect(Keychain.revision(from: Data(repeating: 0x31, count: 1024)) == 0)
        #expect(Keychain.encodeSyncedAccountsSnapshot(accounts: Data("[]".utf8), revision: Data("1".utf8)) != nil)
    }
}
