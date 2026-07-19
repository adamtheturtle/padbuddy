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

@Suite("Preference revision stamps (#2152)")
struct PreferenceRevisionTests {
    @Test
    func `a double stamp reads back unchanged`() {
        #expect(PreferenceCloudSync.revision(1_700_000_000.5) == 1_700_000_000.5)
    }

    @Test
    func `an integer-backed stamp is not lost`() {
        // KVS can hand a whole-numbered stamp back as an integer, which `as? Double`
        // alone rejected — making a genuinely newer cloud write look older than every
        // local one and never be adopted (#2152).
        #expect(PreferenceCloudSync.revision(1_700_000_000) == 1_700_000_000)
        // As KVS actually hands them back: a plist round-trip, which is where the
        // integer-backed representation comes from.
        // swiftlint:disable:next legacy_objc_type
        let bridged = NSNumber(value: 1_700_000_000)
        #expect(PreferenceCloudSync.revision(bridged) == 1_700_000_000)
    }

    @Test
    func `a missing or non-numeric stamp counts as zero`() {
        #expect(PreferenceCloudSync.revision(nil) == 0)
        #expect(PreferenceCloudSync.revision("not a number") == 0)
    }
}

@Suite("Title adoption and survivor de-duplication (#2145, #2146, #2147)")
struct TitleAdoptionAndDedupeTests {
    private struct Favorite: Equatable {
        let id: Int
        var title: String
        let addedAt: Date?
    }

    private func adopt(local: [Favorite], cloud: [Favorite]) -> [Favorite] {
        let account = UUID()
        return FavoriteTitleSync.adoptCloudTitles(
            merged: [account: local],
            cloud: ["identity": cloud],
            uuidForSyncID: { _ in account },
            id: { AnyHashable($0.id) },
            title: \.title
        )[account] ?? []
    }

    @Test
    func `a duplicate cloud id resolves the same way regardless of order`() {
        // Order used to decide the winner, so two devices reading one blob could
        // adopt different titles (#2145).
        let short = Favorite(id: 1, title: "Two", addedAt: nil)
        let long = Favorite(id: 1, title: "Two Sum", addedAt: nil)
        let local = [Favorite(id: 1, title: "old", addedAt: nil)]
        #expect(adopt(local: local, cloud: [short, long]).first?.title == "Two Sum")
        #expect(adopt(local: local, cloud: [long, short]).first?.title == "Two Sum")
    }

    @Test
    func `an empty duplicate never wins`() {
        let blank = Favorite(id: 1, title: "   ", addedAt: nil)
        let real = Favorite(id: 1, title: "Two Sum", addedAt: nil)
        #expect(adopt(local: [Favorite(id: 1, title: "old", addedAt: nil)],
                      cloud: [blank, real]).first?.title == "Two Sum")
    }

    @Test
    func `a title differing only in case or whitespace is not adopted`() {
        // Adopting it wrote a value the other device mirrored back, churning on every
        // sync (#2146).
        let local = [Favorite(id: 1, title: "Two Sum", addedAt: nil)]
        #expect(adopt(local: local, cloud: [Favorite(id: 1, title: "  Two Sum  ", addedAt: nil)])
            .first?.title == "Two Sum")
        #expect(adopt(local: local, cloud: [Favorite(id: 1, title: "TWO SUM", addedAt: nil)])
            .first?.title == "Two Sum")
    }

    @Test
    func `a genuinely different title is still adopted`() {
        let local = [Favorite(id: 1, title: "Old name", addedAt: nil)]
        #expect(adopt(local: local, cloud: [Favorite(id: 1, title: "New name", addedAt: nil)])
            .first?.title == "New name")
    }

    @Test
    func `surviving items are de-duplicated by id`() {
        // The merge feeding this is an additive union, so the same favourite can
        // arrive from two devices and both copies stayed visible (#2147).
        let items = [Favorite(id: 1, title: "a", addedAt: nil),
                     Favorite(id: 1, title: "b", addedAt: nil),
                     Favorite(id: 2, title: "c", addedAt: nil)]
        let resolved = CloudTombstones.resolve(items: items, tombstones: [:],
                                               id: { String($0.id) }, addedAt: \.addedAt)
        #expect(resolved.items.map(\.id) == [1, 2])
    }
}
