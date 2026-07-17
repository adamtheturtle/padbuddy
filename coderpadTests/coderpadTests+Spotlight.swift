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
}
