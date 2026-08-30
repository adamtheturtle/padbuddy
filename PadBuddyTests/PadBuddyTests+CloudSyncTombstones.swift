//
//  PadBuddyTests+CloudSyncTombstones.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Deletion tombstones (#738, #723)")
struct CloudTombstonesTests {
    @Test
    func `a tombstone newer than the entry removes it and survives`() {
        let removed = Date(timeIntervalSince1970: 1000)
        let items = [FavoritePad(id: "abc", title: "T", addedAt: Date(timeIntervalSince1970: 500))]
        let resolved = CloudTombstones.resolve(items: items,
                                               tombstones: ["abc": removed],
                                               id: \.id, addedAt: \.addedAt)
        #expect(resolved.items.isEmpty)
        #expect(resolved.tombstones["abc"] == removed)
    }

    @Test
    func `an entry re-added after the tombstone survives and retires it`() {
        let removed = Date(timeIntervalSince1970: 1000)
        let items = [FavoritePad(id: "abc", title: "T", addedAt: Date(timeIntervalSince1970: 2000))]
        let resolved = CloudTombstones.resolve(items: items,
                                               tombstones: ["abc": removed],
                                               id: \.id, addedAt: \.addedAt)
        #expect(resolved.items.map(\.id) == ["abc"])
        #expect(resolved.tombstones.isEmpty)
    }

    @Test
    func `an entry with no addedAt counts as arbitrarily old`() {
        // Legacy entries persisted before addedAt existed must lose to a tombstone.
        let items = [FavoritePad(id: "abc", title: "T")]
        let resolved = CloudTombstones.resolve(items: items,
                                               tombstones: ["abc": Date(timeIntervalSince1970: 1)],
                                               id: \.id, addedAt: \.addedAt)
        #expect(resolved.items.isEmpty)
    }

    @Test
    func `entries without tombstones pass through untouched`() {
        let items = [FavoritePad(id: "abc", title: "T", addedAt: Date())]
        let resolved = CloudTombstones.resolve(items: items, tombstones: [:],
                                               id: \.id, addedAt: \.addedAt)
        #expect(resolved.items.map(\.id) == ["abc"])
    }

    @Test
    func `open-history entries resolve by their own recency`() {
        let removed = Date(timeIntervalSince1970: 1000)
        let entries = [
            "deleted-pad": Date(timeIntervalSince1970: 500),
            "reopened-pad": Date(timeIntervalSince1970: 2000)
        ]
        let resolved = CloudTombstones.resolveTimestamps(
            entries: entries,
            tombstones: ["deleted-pad": removed, "reopened-pad": removed]
        )
        #expect(resolved.entries.keys.sorted() == ["reopened-pad"])
        #expect(resolved.tombstones.keys.sorted() == ["deleted-pad"])
    }

    @Test
    func `pruning drops tombstones past retention and keeps fresh ones`() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fresh = now.addingTimeInterval(-60)
        let stale = now.addingTimeInterval(-CloudTombstones.retention - 1)
        let pruned = CloudTombstones.pruned(["fresh": fresh, "stale": stale], now: now)
        #expect(pruned.keys.sorted() == ["fresh"])
    }
}

@Suite("Pad-open history hardening (#2606, #2610)")
struct PadOpenedStoreHardeningTests {
    @Test
    func `a far-future timestamp is pulled back to now`() {
        // One device with a badly-set clock otherwise wins every later open on every
        // other device, so those pads look permanently already-read (#2610).
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let entries = [
            "ok": now.addingTimeInterval(-60),
            "future": now.addingTimeInterval(365 * 24 * 60 * 60)
        ]
        let clamped = PadOpenedStore.clampingFutureDates(entries, now: now)
        #expect(clamped["future"] == now)
        #expect(clamped["ok"] == now.addingTimeInterval(-60))
    }

    @Test
    func `ordinary clock skew is left alone`() {
        // A little ahead is normal between machines and must not be rewritten, which
        // would churn the mirror on every sync.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let skewed = now.addingTimeInterval(PadOpenedStore.futureClockTolerance - 1)
        let clamped = PadOpenedStore.clampingFutureDates(["a": skewed], now: now)
        #expect(clamped["a"] == skewed)
    }

    @Test
    func `one corrupt date does not clamp another tolerated future date`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tolerated = now.addingTimeInterval(2 * 60)
        let corrupt = now.addingTimeInterval(365 * 24 * 60 * 60)

        let clamped = PadOpenedStore.clampingFutureDates(
            ["tolerated": tolerated, "corrupt": corrupt], now: now
        )

        #expect(clamped["tolerated"] == tolerated)
        #expect(clamped["corrupt"] == now)
    }

    @Test
    func `the retention cap keeps the most recent opens`() {
        #expect(PadOpenedStore.maxEntriesPerAccount > 0)
    }

    @Test
    func `blank pad ids are not recordable (#4646)`() {
        #expect(PadOpenedStore.normalizedRecordID("") == nil)
        #expect(PadOpenedStore.normalizedRecordID(" \n\t ") == nil)
        #expect(PadOpenedStore.normalizedRecordID(" pad-1 ") == "pad-1")
    }

    @Test
    func `pruning keeps only the newest opens (#4646)`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var entries: [String: Date] = [:]
        for index in 0 ..< 10 {
            entries["pad-\(index)"] = now.addingTimeInterval(TimeInterval(index))
        }

        let pruned = PadOpenedStore.prunedEntries(entries, limit: 3)
        #expect(pruned.count == 3)
        #expect(Set(pruned.keys) == ["pad-7", "pad-8", "pad-9"])
    }

    @Test
    func `tombstones prune even when an account has no live history`() {
        let account = UUID()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let fresh = now.addingTimeInterval(-60)
        let stale = now.addingTimeInterval(-CloudTombstones.retention - 1)

        let result = PadOpenedStore.prunedTombstones(
            [account: ["fresh": fresh, "stale": stale]], liveRecords: [:], now: now
        )
        #expect(result[account] == ["fresh": fresh])
    }

    @Test
    func `live records retire tombstones and empty account maps`() {
        let account = UUID()
        let now = Date(timeIntervalSince1970: 10_000_000)
        let result = PadOpenedStore.prunedTombstones(
            [account: ["reopened": now]], liveRecords: [account: ["reopened": now]], now: now
        )

        #expect(result[account] == nil)
        #expect(result.isEmpty)
    }
}
