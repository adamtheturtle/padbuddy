//
//  coderpadTests+CloudTombstones.swift
//  coderpadTests
//
//  Tombstone resolution and pruning, split from coderpadTests+CloudSync.swift to
//  keep both files under the file-length limit.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Tombstone pruning and re-add resolution (#2148, #2149, #2150)")
struct TombstonePruningTests {
    private struct Item {
        let id: String
        let addedAt: Date?
    }

    private func resolve(_ items: [Item], _ tombstones: [String: Date]) -> [String] {
        CloudTombstones.resolve(items: items, tombstones: tombstones, id: \.id, addedAt: \.addedAt)
            .items.map(\.id)
    }

    @Test
    func `a re-add at the same instant as the removal survives`() {
        // Timestamps come from separate devices with coarse effective resolution, so
        // equal values are common; strict comparison made the re-add vanish (#2148).
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(resolve([Item(id: "a", addedAt: instant)], ["a": instant]) == ["a"])
    }

    @Test
    func `a re-add after the removal survives and an older one does not`() {
        let removed = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(resolve([Item(id: "a", addedAt: removed.addingTimeInterval(1))], ["a": removed]) == ["a"])
        #expect(resolve([Item(id: "a", addedAt: removed.addingTimeInterval(-1))], ["a": removed]).isEmpty)
    }

    @Test
    func `an item with no addedAt still loses to a tombstone`() {
        let removed = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(resolve([Item(id: "a", addedAt: nil)], ["a": removed]).isEmpty)
    }

    @Test
    func `a future-dated tombstone is discarded`() {
        // A bad clock could otherwise suppress an item permanently (#2149).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pruned = CloudTombstones.pruned(["a": now.addingTimeInterval(60 * 60 * 24)], now: now)
        #expect(pruned.isEmpty)
    }

    @Test
    func `small clock skew is tolerated`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(CloudTombstones.pruned(["a": now.addingTimeInterval(30)], now: now).count == 1)
    }

    @Test
    func `expired tombstones are dropped and recent ones kept`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pruned = CloudTombstones.pruned([
            "old": now.addingTimeInterval(-CloudTombstones.retention - 1),
            "new": now.addingTimeInterval(-60)
        ], now: now)
        #expect(pruned.keys.sorted() == ["new"])
    }

    @Test
    func `tombstones are capped, keeping the newest`() {
        // Churn could otherwise build a KVS payload large enough to fail to sync (#2150).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let many = Dictionary(uniqueKeysWithValues: (0 ..< (CloudTombstones.maxTombstones + 50)).map {
            ("k\($0)", now.addingTimeInterval(-Double($0)))
        })
        let pruned = CloudTombstones.pruned(many, now: now)
        #expect(pruned.count == CloudTombstones.maxTombstones)
        // Index 0 is the newest, so it must survive; the oldest must not.
        #expect(pruned["k0"] != nil)
        #expect(pruned["k\(CloudTombstones.maxTombstones + 49)"] == nil)
    }
}
