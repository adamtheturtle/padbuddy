//
//  PadBuddyTests+PadOpenedReconciliation.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad opened reconciliation")
struct PadOpenedReconciliationTests {
    @Test
    func `authoritative pad reconciliation keeps present records and identifies vanished pads`() {
        let opened = Date(timeIntervalSince1970: 1000)
        let entries = ["present": opened, "vanished": opened]

        let result = PadOpenedStore.reconciledOpenRecords(entries, presentPadIDs: ["present"])

        #expect(result.kept == ["present": opened])
        #expect(result.removedIDs == ["vanished"])
    }

    @Test
    func `empty authoritative list removes every recorded pad`() {
        let entries = ["one": Date(timeIntervalSince1970: 1), "two": Date(timeIntervalSince1970: 2)]

        let result = PadOpenedStore.reconciledOpenRecords(entries, presentPadIDs: [])

        #expect(result.kept.isEmpty)
        #expect(result.removedIDs == ["one", "two"])
    }
}

@Suite("Pad-open pruning tombstones (#4735)")
struct PadOpenedPruningTests {
    private func entries(_ count: Int) -> [String: Date] {
        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        return Dictionary(uniqueKeysWithValues: (0 ..< count).map {
            ("pad-\($0)", base.addingTimeInterval(Double($0)))
        })
    }

    @Test func `nothing is dropped below the cap`() {
        #expect(PadOpenedStore.droppedByPruning(entries(3), limit: 5).isEmpty)
    }

    @Test func `the oldest records are the ones dropped`() {
        // These must be tombstoned: an untombstoned drop is merged back from a device
        // that has not pruned yet, so the cap never actually holds.
        let dropped = PadOpenedStore.droppedByPruning(entries(6), limit: 4)

        #expect(dropped == ["pad-0", "pad-1"])
    }

    @Test func `the dropped set is exactly what pruning removes`() {
        let all = entries(10)

        let kept = PadOpenedStore.prunedEntries(all, limit: 4)
        let dropped = PadOpenedStore.droppedByPruning(all, limit: 4)

        #expect(Set(kept.keys).union(dropped) == Set(all.keys))
        #expect(Set(kept.keys).isDisjoint(with: dropped))
    }

    @Test func `equal timestamps prune by stable pad id regardless of insertion order`() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let forward = Dictionary(uniqueKeysWithValues: ["d", "b", "a", "c"].map { ($0, date) })
        let reverse = Dictionary(uniqueKeysWithValues: ["c", "a", "b", "d"].map { ($0, date) })

        let forwardKept = PadOpenedStore.prunedEntries(forward, limit: 2)
        let reverseKept = PadOpenedStore.prunedEntries(reverse, limit: 2)

        #expect(Set(forwardKept.keys) == ["a", "b"])
        #expect(forwardKept == reverseKept)
        #expect(PadOpenedStore.droppedByPruning(forward, limit: 2)
            == PadOpenedStore.droppedByPruning(reverse, limit: 2))
    }
}
