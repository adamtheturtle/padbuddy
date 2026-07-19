//
//  KeychainAccountStoreTests.swift
//  BuddyAppKitTests
//
//  Deterministic, UI-free coverage of the generic account store's in-memory logic
//  (#513): the testing-mode seed, selection resolution, add/update/remove, the
//  rekey/remove hooks, and the merged-view rule. Runs in testing mode so it never
//  touches the real Keychain or UserDefaults.
//

import BuddyAppKit
import Foundation
import os
import Testing

private struct MockAccount: StorableAccount, Equatable {
    let accountID: UUID
    var key: String

    func pointsAtDifferentBackend(than other: MockAccount) -> Bool {
        key != other.key
    }
}

@MainActor
private func makeStore(
    seed: [MockAccount],
    onRemoved: @escaping @MainActor (UUID) -> Void = { _ in },
    onRekeyed: @escaping @MainActor (UUID) -> Void = { _ in }
) -> KeychainAccountStore<MockAccount> {
    let config = KeychainAccountStore<MockAccount>.Config(
        keychain: KeychainStore(service: "test.buddyappkit.unused", logger: Logger(subsystem: "test", category: "x")),
        accountsKey: "accounts",
        currentIDDefaultsKey: "current",
        showAllAccountsDefaultsKey: "showAll",
        encode: { _ in nil },
        decode: { _ in [] },
        isTestingMode: true,
        seedForTesting: { seed },
        migrateIfEmpty: { nil },
        onAccountsChanged: { _ in },
        onCurrentChanged: { _ in },
        onRemoved: onRemoved,
        onRekeyed: onRekeyed,
        logger: Logger(subsystem: "test", category: "x")
    )
    return KeychainAccountStore(config: config)
}

@Suite("KeychainAccountStore in-memory logic")
@MainActor
struct KeychainAccountStoreTests {
    @Test
    func `testing mode seeds the accounts and selects the first`() {
        let a = MockAccount(accountID: UUID(), key: "a")
        let store = makeStore(seed: [a])
        #expect(store.accounts.count == 1)
        #expect(store.currentAccountID == a.accountID)
        #expect(store.currentAccount == a)
    }

    @Test
    func `add appends and selects when nothing is current`() {
        let store = makeStore(seed: [])
        #expect(store.currentAccountID == nil)

        let a = MockAccount(accountID: UUID(), key: "a")
        store.add(a)
        #expect(store.accounts == [a])
        #expect(store.currentAccountID == a.accountID)
    }

    @Test
    func `add upserts an existing account ID`() {
        let id = UUID()
        let original = MockAccount(accountID: id, key: "a")
        let replacement = MockAccount(accountID: id, key: "b")
        var rekeyed: [UUID] = []
        let store = makeStore(seed: [original], onRekeyed: { rekeyed.append($0) })

        store.add(replacement)

        #expect(store.accounts == [replacement])
        #expect(store.currentAccountID == id)
        #expect(rekeyed == [id])
    }

    @Test
    func `update fires onRekeyed only when the backend changes`() {
        let id = UUID()
        var rekeyed: [UUID] = []
        let store = makeStore(seed: [MockAccount(accountID: id, key: "a")], onRekeyed: { rekeyed.append($0) })

        store.update(MockAccount(accountID: id, key: "a")) // same key → no rekey
        #expect(rekeyed.isEmpty)

        store.update(MockAccount(accountID: id, key: "b")) // changed key → rekey
        #expect(rekeyed == [id])
    }

    @Test
    func `remove drops the account, reselects, and fires onRemoved`() {
        let first = MockAccount(accountID: UUID(), key: "a")
        let second = MockAccount(accountID: UUID(), key: "b")
        var removed: [UUID] = []
        let store = makeStore(seed: [first, second], onRemoved: { removed.append($0) })

        store.remove(id: first.accountID)
        #expect(store.accounts == [second])
        #expect(store.currentAccountID == second.accountID) // reselected the survivor
        #expect(removed == [first.accountID])
    }

    @Test
    func `merged view needs the opt-in and at least two accounts`() {
        let store = makeStore(seed: [MockAccount(accountID: UUID(), key: "a")])
        store.showAllAccounts = true
        #expect(!store.isMergedView) // opted in but only one account

        store.add(MockAccount(accountID: UUID(), key: "b"))
        #expect(store.isMergedView)
    }
}
