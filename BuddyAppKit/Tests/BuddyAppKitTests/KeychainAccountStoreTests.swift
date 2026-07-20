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
    onAccountsChanged: @escaping @MainActor ([MockAccount]) -> Void = { _ in },
    onCurrentChanged: @escaping @MainActor (MockAccount?) -> Void = { _ in },
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
        onAccountsChanged: onAccountsChanged,
        onCurrentChanged: onCurrentChanged,
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
    func `initialization keeps the first account for each ID`() {
        let repeatedID = UUID()
        let first = MockAccount(accountID: repeatedID, key: "first")
        let duplicate = MockAccount(accountID: repeatedID, key: "duplicate")
        let distinct = MockAccount(accountID: UUID(), key: "distinct")

        let store = makeStore(seed: [first, duplicate, distinct])

        #expect(store.accounts == [first, distinct])
        #expect(store.currentAccount == first)
    }

    @Test
    func `invalid selection normalizes to the first account and notifies once`() {
        let first = MockAccount(accountID: UUID(), key: "first")
        let second = MockAccount(accountID: UUID(), key: "second")
        var notifications: [MockAccount?] = []
        let store = makeStore(seed: [first, second], onCurrentChanged: { notifications.append($0) })
        notifications.removeAll()

        store.currentAccountID = UUID()

        #expect(store.currentAccountID == first.accountID)
        #expect(store.currentAccount == first)
        #expect(notifications == [first])
    }

    @Test
    func `invalid selection normalizes to nil when there are no accounts`() {
        var notifications: [MockAccount?] = []
        let store = makeStore(seed: [], onCurrentChanged: { notifications.append($0) })
        notifications.removeAll()

        store.currentAccountID = UUID()

        #expect(store.currentAccountID == nil)
        #expect(store.currentAccount == nil)
        #expect(notifications == [nil])
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
    func `update invalidates a changed backend before publishing it`() {
        let id = UUID()
        var events: [String] = []
        let store = makeStore(
            seed: [MockAccount(accountID: id, key: "old")],
            onAccountsChanged: { accounts in events.append("published:\(accounts[0].key)") },
            onRekeyed: { _ in events.append("rekeyed") }
        )

        store.update(MockAccount(accountID: id, key: "new"))

        #expect(events == ["rekeyed", "published:new"])
    }

    @Test
    func `update without a backend change publishes without invalidation`() {
        let id = UUID()
        var events: [String] = []
        let store = makeStore(
            seed: [MockAccount(accountID: id, key: "same")],
            onAccountsChanged: { _ in events.append("published") },
            onRekeyed: { _ in events.append("rekeyed") }
        )

        store.update(MockAccount(accountID: id, key: "same"))

        #expect(events == ["published"])
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
    func `remove cleans up before publishing accounts or selection`() {
        let first = MockAccount(accountID: UUID(), key: "a")
        let second = MockAccount(accountID: UUID(), key: "b")
        var events: [String] = []
        let store = makeStore(
            seed: [first, second],
            onAccountsChanged: { _ in events.append("accounts") },
            onCurrentChanged: { _ in events.append("current") },
            onRemoved: { _ in events.append("removed") }
        )
        events.removeAll()

        store.remove(id: first.accountID)

        #expect(events == ["removed", "accounts", "current"])
    }

    @Test
    func `removing an unknown account has no side effects`() {
        let account = MockAccount(accountID: UUID(), key: "a")
        var events: [String] = []
        let store = makeStore(
            seed: [account],
            onAccountsChanged: { _ in events.append("accounts") },
            onCurrentChanged: { _ in events.append("current") },
            onRemoved: { _ in events.append("removed") }
        )
        events.removeAll()

        store.remove(id: UUID())

        #expect(events.isEmpty)
        #expect(store.accounts == [account])
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
