//
//  PadBuddyTests+Spotlight.swift
//  PadBuddyTests
//
//  Spotlight indexed-identifier persistence: the bookkeeping that lets stale-item
//  reconciliation span launches (#733).
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Spotlight identifier persistence")
struct SpotlightIdentifierPersistenceTests {
    @Test
    func `base records are skipped only after successful acknowledgement`() {
        let identifier = "pad:\(UUID().uuidString):ABC123"
        let original = SpotlightIndexer.PadIndexRecord(
            identifier: identifier, title: "Interview", description: "Active"
        )
        defer {
            SpotlightIndexer.enrichmentLock.withLock {
                _ = SpotlightIndexer.indexedPadFingerprints.removeValue(forKey: identifier)
            }
        }

        #expect(SpotlightIndexer.changedPadRecords([original]).count == 1)
        SpotlightIndexer.acknowledgePadRecords([original])
        #expect(SpotlightIndexer.changedPadRecords([original]).isEmpty)

        let changed = SpotlightIndexer.PadIndexRecord(
            identifier: identifier, title: "Renamed", description: "Active"
        )
        #expect(SpotlightIndexer.changedPadRecords([changed]).count == 1)
    }

    @Test
    func `an identifier map round-trips through its plist encoding (#733)`() {
        let accountA = UUID()
        let accountB = UUID()
        let map: [UUID: Set<String>] = [
            accountA: ["pad:abc", "pad:def"],
            accountB: []
        ]
        let encoded = SpotlightIndexer.encodeIdentifierMap(map)
        #expect(SpotlightIndexer.decodeIdentifierMap(encoded) == map)
    }

    @Test
    func `decoding skips corrupt account keys without sinking valid ones`() {
        let account = UUID()
        let raw = [account.uuidString: ["pad:abc"], "not-a-uuid": ["pad:zzz"]]
        let decoded = SpotlightIndexer.decodeIdentifierMap(raw)
        #expect(decoded == [account: Set(["pad:abc"])])
    }

    @Test
    func `pad identifiers are account-namespaced and round-trip with the account (#759)`() {
        let account = UUID()
        let identifier = SpotlightIndexer.padIdentifier(id: "abc123", account: account)
        #expect(identifier == "pad:\(account.uuidString):abc123")

        let ref = SpotlightIndexer.padRef(fromItemIdentifier: identifier)
        #expect(ref?.account == account)
        #expect(ref?.id == "abc123")

        // Items indexed before the namespacing carry no account but still parse.
        let legacy = SpotlightIndexer.padRef(fromItemIdentifier: "pad:ABC123")
        #expect(legacy?.account == nil)
        #expect(legacy?.id == "ABC123")

        #expect(SpotlightIndexer.padRef(fromItemIdentifier: "question:42") == nil)
        #expect(SpotlightIndexer.padRef(fromItemIdentifier: "pad:") == nil)
        // Since #1731, ids normalize through PadIDValidation (ASCII letters and
        // numbers only), so a colon-carrying body that isn't a valid namespaced
        // identifier is rejected rather than treated as one legacy slug.
        #expect(SpotlightIndexer.padRef(fromItemIdentifier: "pad:not-a-uuid:xyz") == nil)
    }

    /// A namespaced identifier that ends at the account (`pad:<uuid>:`) is
    /// corrupt: it must be rejected, not routed as a legacy pad whose slug is
    /// the UUID-and-colon body (#1965).
    @Test
    func `a namespaced pad identifier with no trailing pad id is rejected`() {
        let account = UUID()
        #expect(SpotlightIndexer.padRef(fromItemIdentifier: "pad:\(account.uuidString):") == nil)
        #expect(SpotlightIndexer.padRef(fromItemIdentifier: "pad:\(account.uuidString)") == nil)
        #expect(SpotlightIndexer.padRef(fromItemIdentifier: "pad:\(account.uuidString): ") == nil)
    }

    /// Server question ids are positive; zero or negative values only come from
    /// crafted or corrupted identifiers and must not navigate (#1966).
    @Test
    func `non-positive question ids are rejected`() {
        let account = UUID()
        #expect(SpotlightIndexer.questionRef(fromItemIdentifier: "question:\(account.uuidString):42")?.id == 42)
        #expect(SpotlightIndexer.questionRef(fromItemIdentifier: "question:\(account.uuidString):0") == nil)
        #expect(SpotlightIndexer.questionRef(fromItemIdentifier: "question:\(account.uuidString):-7") == nil)
    }
}
