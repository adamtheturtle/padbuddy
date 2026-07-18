//
//  coderpadTests+Spotlight.swift
//  coderpadTests
//
//  Spotlight indexed-identifier persistence: the bookkeeping that lets stale-item
//  reconciliation span launches (#733).
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Spotlight identifier persistence")
struct SpotlightIdentifierPersistenceTests {
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
        // A slug that merely contains a colon without a UUID prefix stays one id.
        let colonSlug = SpotlightIndexer.padRef(fromItemIdentifier: "pad:not-a-uuid:xyz")
        #expect(colonSlug?.account == nil)
        #expect(colonSlug?.id == "not-a-uuid:xyz")
    }
}
