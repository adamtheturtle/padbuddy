//
//  PadBuddyTests+PadMutationRevisions.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad mutation ordering (#1332)")
struct PadMutationRevisionTests {
    @Test
    func `deletion invalidates an older end refresh without crossing scopes`() throws {
        var revisions = PadMutationRevisionStore()
        let account = UUID()
        let otherAccount = UUID()
        let client = try ClientTaskIdentity(
            apiKey: "key", baseURL: #require(URL(string: "https://example.com"))
        )
        let key = PadMutationRevisionStore.Key(accountID: account, padID: "pad", clientIdentity: client)
        let other = PadMutationRevisionStore.Key(accountID: otherAccount, padID: "pad", clientIdentity: client)
        let endRefresh = revisions.claim(key)
        let unrelated = revisions.claim(other)

        revisions.invalidate(key)
        let later = revisions.claim(key)

        #expect(!revisions.isCurrent(endRefresh))
        #expect(revisions.isCurrent(unrelated))
        #expect(revisions.isCurrent(later))
    }
}

@Suite("Pad mutation revision retention (#4546)")
struct PadMutationRevisionRetentionTests {
    private func key(account: UUID = UUID(), pad: String = "pad") -> PadMutationRevisionStore.Key {
        PadMutationRevisionStore.Key(
            accountID: account, padID: pad,
            clientIdentity: ClientTaskIdentity(apiKey: "k", baseURL: URL(string: "https://x")!)
        )
    }

    @Test func `releasing the last claim drops the entry`() {
        var store = PadMutationRevisionStore()
        let claim = store.claim(key())

        store.release(claim)

        #expect(store.trackedKeyCount == 0)
    }

    @Test func `an entry survives until every outstanding claim is released`() {
        var store = PadMutationRevisionStore()
        let target = key()
        let first = store.claim(target)
        let second = store.claim(target)

        store.release(first)

        #expect(store.trackedKeyCount == 1)
        // The superseded claim is still not current: a newer mutation took over.
        #expect(!store.isCurrent(first))
        #expect(store.isCurrent(second))
        store.release(second)
        #expect(store.trackedKeyCount == 0)
    }

    @Test func `a recreated entry does not make a stale claim current again`() {
        var store = PadMutationRevisionStore()
        let target = key()
        let stale = store.claim(target)
        store.release(stale)

        let fresh = store.claim(target)

        #expect(store.isCurrent(fresh))
        #expect(!store.isCurrent(stale))
    }

    @Test func `invalidating an idle key does not retain it`() {
        var store = PadMutationRevisionStore()

        store.invalidate(key())

        #expect(store.trackedKeyCount == 0)
    }

    @Test func `removing an account drops only that account's keys`() {
        var store = PadMutationRevisionStore()
        let removed = UUID()
        let kept = UUID()
        _ = store.claim(key(account: removed))
        _ = store.claim(key(account: kept))

        store.removeAll(accountID: removed)

        #expect(store.trackedKeyCount == 1)
    }

    @Test func `removing a client identity drops its keys`() throws {
        var store = PadMutationRevisionStore()
        let identity = try ClientTaskIdentity(apiKey: "k", baseURL: #require(URL(string: "https://x")))
        _ = store.claim(key())

        store.removeAll(clientIdentity: identity)

        #expect(store.trackedKeyCount == 0)
    }
}
