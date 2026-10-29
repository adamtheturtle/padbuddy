//
//  PadBuddyTests+Keychain.swift
//  PadBuddyTests
//
//  Credential service identity and account snapshot reconciliation.
//

import Foundation
@testable import PadBuddy
import Security
import Testing

@Suite("Keychain service compatibility")
struct KeychainServiceTests {
    @Test
    func `credentials use the PadBuddy service`() {
        #expect(Keychain.service == "com.adamdangoor.padbuddy")
    }

    @Test @MainActor
    func `unit test hosts use ephemeral accounts and cannot read real credentials`() {
        #expect(coderpadIsHostingUnitTests)
        #expect(padBuddyUsesInMemoryAccounts)
        #expect(AccountsStore.shared.readFailureStatus == nil)
        #expect(Keychain.readData(account: Keychain.accountsAccount) == nil)
        #expect(Keychain.readSynchronizableData(account: Keychain.accountsAccount) == nil)
        #expect(!Keychain.accountsSnapshotIsDefinitivelyAbsent())
    }

    @Test
    func `the account-name keys are unchanged`() {
        #expect(Keychain.accountsAccount == "accounts")
        #expect(Keychain.syncedAccountsSnapshotAccount == "accountsSnapshotV2")
        #expect(Keychain.legacySingleKeyAccount == "apiKey")
    }
}

@Suite("Synchronizable Keychain diagnostics")
struct SynchronizableKeychainDiagnosticsTests {
    @Test
    func `missing entitlement is an expected cloud-unavailable state`() {
        #expect(!Keychain.synchronizableFailureRequiresLogging(errSecSuccess))
        #expect(!Keychain.synchronizableFailureRequiresLogging(errSecMissingEntitlement))
        #expect(Keychain.synchronizableFailureRequiresLogging(errSecAuthFailed))
    }

    @Test
    func `missing items are ignored only where the operation permits them`() {
        #expect(Keychain.synchronizableFailureRequiresLogging(errSecItemNotFound))
        #expect(!Keychain.synchronizableFailureRequiresLogging(errSecItemNotFound, permitsMissingItem: true))
    }
}

@Suite("Atomic synced account snapshots")
struct AtomicSyncedAccountSnapshotTests {
    @Test
    func `account bytes and revision round-trip as one item`() throws {
        let accounts = Data("accounts".utf8)
        let revision = Data("123.5".utf8)
        let encoded = try #require(Keychain.encodeSyncedAccountsSnapshot(accounts: accounts, revision: revision))

        let decoded = try #require(Keychain.decodeSyncedAccountsSnapshot(encoded))
        #expect(decoded.accounts == accounts)
        #expect(decoded.revision == revision)
    }

    @Test
    func `snapshot rejects an invalid revision`() throws {
        let encoded = try #require(Keychain.encodeSyncedAccountsSnapshot(
            accounts: Data("accounts".utf8),
            revision: Data("not-a-revision".utf8)
        ))

        #expect(Keychain.decodeSyncedAccountsSnapshot(encoded) == nil)
    }

    @Test
    func `legacy pair must be strictly newer than atomic snapshot`() {
        let atomic = Keychain.SyncedAccountsSnapshot(
            accounts: Data("atomic".utf8), revision: Data("10".utf8)
        )
        let interruptedLegacy = Keychain.SyncedAccountsSnapshot(
            accounts: Data("new bytes, old stamp".utf8), revision: Data("10".utf8)
        )
        let completedLegacy = Keychain.SyncedAccountsSnapshot(
            accounts: Data("new bytes, new stamp".utf8), revision: Data("11".utf8)
        )

        #expect(Keychain.newestSyncedSnapshot(atomic: atomic, legacy: interruptedLegacy) == atomic)
        #expect(Keychain.newestSyncedSnapshot(atomic: atomic, legacy: completedLegacy) == completedLegacy)
    }

    @Test
    func `malformed newer atomic payload falls back to usable legacy mirror`() {
        let atomic = Keychain.SyncedAccountsSnapshot(
            accounts: Data("malformed".utf8), revision: Data("20".utf8)
        )
        let legacy = Keychain.SyncedAccountsSnapshot(
            accounts: Data("usable legacy".utf8), revision: Data("10".utf8)
        )

        let selected = Keychain.newestUsableSyncedSnapshot(
            atomic: atomic,
            legacy: legacy,
            isUsable: { $0 == legacy.accounts }
        )

        #expect(selected == legacy)
    }

    @Test
    func `unknown cloud schemas remain present instead of looking absent`() {
        let atomic = Keychain.SyncedAccountsSnapshot(
            accounts: Data("unknown atomic".utf8), revision: Data("20".utf8)
        )
        let legacy = Keychain.SyncedAccountsSnapshot(
            accounts: Data("unknown legacy".utf8), revision: Data("10".utf8)
        )

        let selected = Keychain.newestUsableSyncedSnapshot(
            atomic: atomic,
            legacy: legacy,
            isUsable: { _ in false }
        )

        #expect(selected == atomic)
    }
}

@Suite("Keychain reconciliation ordering")
struct KeychainReconciliationOrderingTests {
    @Test
    func `equal revisions choose the same bytes on both device orientations`() {
        let lower = Data("account-a".utf8)
        let higher = Data("account-b".utf8)

        #expect(Keychain.shouldAdoptCloud(local: lower, cloud: higher,
                                          localRevision: 10, cloudRevision: 10))
        #expect(!Keychain.shouldAdoptCloud(local: higher, cloud: lower,
                                           localRevision: 10, cloudRevision: 10))
    }

    @Test
    func `revision ordering remains authoritative`() {
        let local = Data("z".utf8)
        let cloud = Data("a".utf8)

        #expect(Keychain.shouldAdoptCloud(local: local, cloud: cloud,
                                          localRevision: 10, cloudRevision: 11))
        #expect(!Keychain.shouldAdoptCloud(local: local, cloud: cloud,
                                           localRevision: 11, cloudRevision: 10))
    }

    @Test
    func `only positive finite cloud revisions are preserved`() {
        #expect(Keychain.normalizedRevisionData(Data("123.5".utf8)) == Data("123.5".utf8))
        for invalid in [nil, Data("bad".utf8), Data("0".utf8), Data("-1".utf8), Data("nan".utf8)] {
            #expect(Keychain.normalizedRevisionData(invalid) == nil)
        }
    }

    @Test
    func `logical revision advances beyond every observed replica`() {
        let next = Keychain.nextRevisionData([
            Data("12".utf8), Data("100.5".utf8), Data("bad".utf8), nil
        ])
        #expect(next == Data("101.5".utf8))
        #expect(Keychain.nextRevisionData([]) == Data("1.0".utf8))
    }
}

@Suite("Synced account validation")
@MainActor
struct SyncedAccountValidationTests {
    @Test
    func `valid and genuinely empty account lists are usable`() throws {
        let valid = Account(name: "Acme", apiKey: "key", userEmail: "")

        #expect(try Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode([valid])))
        #expect(Keychain.decodesToUsableAccounts(Data("[]".utf8)))
    }

    @Test
    func `empty keys and malformed endpoints are rejected`() throws {
        let emptyKey = Account(name: "Acme", apiKey: "   ")
        let badEndpoint = Account(name: "Acme", apiKey: "key", baseURL: "not a URL")

        #expect(try !Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode([emptyKey])))
        #expect(try !Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode([badEndpoint])))
    }

    @Test
    func `duplicate IDs and partially malformed lists are rejected`() throws {
        let id = UUID()
        let duplicates = [Account(name: "A", apiKey: "a", id: id), Account(name: "B", apiKey: "b", id: id)]
        #expect(try !Keychain.decodesToUsableAccounts(Keychain.accountEncoder.encode(duplicates)))

        let validJSON = try #require(String(data: Keychain.accountEncoder.encode([duplicates[0]]), encoding: .utf8))
        let partial = "[\(validJSON.dropFirst().dropLast()),{\"name\":\"missing required fields\"}]"
        #expect(!Keychain.decodesToUsableAccounts(Data(partial.utf8)))
    }
}
