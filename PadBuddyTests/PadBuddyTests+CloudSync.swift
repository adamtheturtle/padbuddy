//
//  PadBuddyTests+CloudSync.swift
//  PadBuddyTests
//
//  Tests for the iCloud-sync foundation (#536): the stable cross-device account
//  identity and the pure merge helpers that move per-account collections between
//  their local (UUID-keyed) and cloud (sync-id-keyed) forms. The iCloud I/O itself
//  (`CloudSyncStore`) needs the entitlement + a second device, so it's verified
//  separately; the logic that decides what syncs is exercised here.
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("iCloud sync foundation")
struct CloudSyncTests {
    @Test
    func `projecting to cloud keys by sync id and drops accounts with no stable id`() {
        let live = UUID()
        let draft = UUID()
        let identities = [live: "host|jane@acme.com", draft: ""]

        let cloud = CloudSyncMerge.toCloud([live: ["pad-1", "pad-2"], draft: ["pad-x"]]) {
            identities[$0]
        }

        #expect(cloud == ["host|jane@acme.com": ["pad-1", "pad-2"]])
    }

    @Test
    func `merging unions cloud favourites into local without losing or deleting any`() {
        let local = UUID()
        let identity = "host|jane@acme.com"

        let merged = CloudSyncMerge.mergeArrays(
            cloud: [identity: ["pad-2", "pad-3"]],
            into: [local: ["pad-1", "pad-2"]]
        ) { $0 == identity ? local : nil }

        // Local order preserved, the cloud-only "pad-3" appended, "pad-2" not doubled,
        // and the local-only "pad-1" untouched (deletions don't propagate in v1).
        #expect(merged[local] == ["pad-1", "pad-2", "pad-3"])
    }

    @Test
    func `merging adopts cloud favourites for an account that is empty locally`() {
        let local = UUID()
        let identity = "host|jane@acme.com"

        let merged = CloudSyncMerge.mergeArrays(
            cloud: [identity: ["pad-9"]],
            into: [:]
        ) { $0 == identity ? local : nil }

        #expect(merged[local] == ["pad-9"])
    }

    @Test
    func `merging ignores cloud entries for accounts not configured on this device`() {
        let local = UUID()

        let merged = CloudSyncMerge.mergeArrays(
            cloud: ["host|someone-else@acme.com": ["pad-7"]],
            into: [local: ["pad-1"]]
        ) { _ in nil }

        #expect(merged == [local: ["pad-1"]])
    }

    // MARK: id-keyed union (favourite questions, templates)

    private struct Item: Equatable {
        let id: Int
        var label: String
    }

    @Test
    func `id-keyed merge unions by id and keeps the local entry when both have it`() {
        let local = UUID()
        let identity = "host|jane@acme.com"

        let merged = CloudSyncMerge.mergeArrays(
            cloud: [identity: [Item(id: 2, label: "cloud-renamed"), Item(id: 3, label: "from-cloud")]],
            into: [local: [Item(id: 1, label: "local"), Item(id: 2, label: "local-2")]],
            uuidForSyncID: { $0 == identity ? local : nil },
            id: { $0.id }
        )

        // id 2 stays as the local copy (not overwritten by the cloud's renamed label),
        // the cloud-only id 3 is appended, and local order holds.
        #expect(merged[local] == [
            Item(id: 1, label: "local"),
            Item(id: 2, label: "local-2"),
            Item(id: 3, label: "from-cloud")
        ])
    }

    @Test
    func `id-keyed merge adopts cloud items for an account empty locally`() {
        let local = UUID()
        let identity = "host|jane@acme.com"

        let merged = CloudSyncMerge.mergeArrays(
            cloud: [identity: [Item(id: 5, label: "x")]],
            into: [:],
            uuidForSyncID: { $0 == identity ? local : nil },
            id: { $0.id }
        )

        #expect(merged[local] == [Item(id: 5, label: "x")])
    }

    // MARK: nested id-keyed union (saved searches, per kind)

    @Test
    func `nested merge unions each bucket by id independently`() {
        let local = UUID()
        let identity = "host|jane@acme.com"

        let merged = CloudSyncMerge.mergeNestedArrays(
            cloud: [identity: [
                "pads": [Item(id: 2, label: "cloud"), Item(id: 9, label: "cloud-only")],
                "questions": [Item(id: 1, label: "q-cloud")]
            ]],
            into: [local: [
                "pads": [Item(id: 2, label: "local")]
            ]],
            uuidForSyncID: { $0 == identity ? local : nil },
            id: { $0.id }
        )

        // pads: id 2 kept local, id 9 appended; questions bucket adopted wholesale.
        #expect(merged[local]?["pads"] == [Item(id: 2, label: "local"), Item(id: 9, label: "cloud-only")])
        #expect(merged[local]?["questions"] == [Item(id: 1, label: "q-cloud")])
    }

    // MARK: timestamp union (pad open history)

    @Test
    func `timestamp merge keeps the most recent open per pad across devices`() {
        let local = UUID()
        let identity = "host|jane@acme.com"
        let earlier = Date(timeIntervalSince1970: 1000)
        let later = Date(timeIntervalSince1970: 2000)

        let merged = CloudSyncMerge.mergeTimestamps(
            cloud: [identity: ["pad-1": later, "pad-2": earlier, "pad-3": later]],
            into: [local: ["pad-1": earlier, "pad-2": later]]
        ) { $0 == identity ? local : nil }

        // pad-1 advances to the newer cloud time, pad-2 keeps the newer local time, and
        // the cloud-only pad-3 is adopted — never an older time winning.
        #expect(merged[local] == ["pad-1": later, "pad-2": later, "pad-3": later])
    }

    @Test
    func `timestamp merge adopts cloud history for an account empty locally and ignores unknown accounts`() {
        let local = UUID()
        let identity = "host|jane@acme.com"
        let opened = Date(timeIntervalSince1970: 5000)

        let adopted = CloudSyncMerge.mergeTimestamps(
            cloud: [identity: ["pad-9": opened]],
            into: [:]
        ) { $0 == identity ? local : nil }
        #expect(adopted[local] == ["pad-9": opened])

        let unchanged = CloudSyncMerge.mergeTimestamps(
            cloud: ["host|other@acme.com": ["pad-7": opened]],
            into: [local: ["pad-1": opened]]
        ) { _ in nil }
        #expect(unchanged == [local: ["pad-1": opened]])
    }

    // MARK: app-global preference sync

    @Test
    func `preference value comparison drives convergence and treats absent as equal`() {
        // Equal values stop a push/pull, which is what makes the sync converge.
        #expect(PreferenceCloudSync.plistValuesEqual("dark", "dark"))
        #expect(PreferenceCloudSync.plistValuesEqual(30, 30))
        #expect(PreferenceCloudSync.plistValuesEqual(true, true))
        #expect(PreferenceCloudSync.plistValuesEqual(nil, nil))
        // Differences trigger a sync.
        #expect(!PreferenceCloudSync.plistValuesEqual("dark", "light"))
        #expect(!PreferenceCloudSync.plistValuesEqual(30, 60))
        #expect(!PreferenceCloudSync.plistValuesEqual("dark", nil))
        #expect(!PreferenceCloudSync.plistValuesEqual(nil, "dark"))
    }

    @Test
    func `sensitive preferences are excluded from sync`() {
        // A representative legacy credential preference must never sync; a representative
        // continuity preference must.
        #expect(!PreferenceCloudSync.syncedKeys.contains("coderPadAPIKey"))
        #expect(PreferenceCloudSync.syncedKeys.contains("general.appearance"))
    }

    @Test
    func `badge denial only disables the unchanged pulled scope`() {
        #expect(PreferenceCloudSync.shouldDisableBadgeScope(
            pulled: .allAccounts, current: .allAccounts, authorizationIsAvailable: false
        ))
        #expect(!PreferenceCloudSync.shouldDisableBadgeScope(
            pulled: .allAccounts, current: .currentAccount, authorizationIsAvailable: false
        ))
        #expect(!PreferenceCloudSync.shouldDisableBadgeScope(
            pulled: .allAccounts, current: .allAccounts, authorizationIsAvailable: true
        ))
    }

    @Test
    func `notification denial only disables the current request`() {
        #expect(PreferenceCloudSync.shouldDisableNotifications(
            requestedGeneration: 4, currentGeneration: 4,
            notificationsAreEnabled: true, authorizationIsAvailable: false
        ))
        #expect(!PreferenceCloudSync.shouldDisableNotifications(
            requestedGeneration: 4, currentGeneration: 5,
            notificationsAreEnabled: true, authorizationIsAvailable: false
        ))
        #expect(!PreferenceCloudSync.shouldDisableNotifications(
            requestedGeneration: 4, currentGeneration: 4,
            notificationsAreEnabled: false, authorizationIsAvailable: false
        ))
    }
}

@Suite("Favorite title adoption (#762)")
struct FavoriteTitleSyncTests {
    @Test
    func `a title renamed on another device is adopted for a shared id`() {
        let account = UUID()
        let merged = [account: [FavoritePad(id: "abc", title: "Old title")]]
        let cloud = ["sync-id": [FavoritePad(id: "abc", title: "New title")]]
        let result = FavoriteTitleSync.adoptCloudTitles(
            merged: merged, cloud: cloud, uuidForSyncID: { _ in account },
            id: { $0.id }, title: \.title
        )
        #expect(result[account]?.map(\.title) == ["New title"])
    }

    @Test
    func `an empty cloud title never blanks a captured local one`() {
        // Legacy id-only favorites carry empty titles; they must not erase a
        // title this device already captured.
        let account = UUID()
        let merged = [account: [FavoriteQuestion(id: 7, title: "Two Sum")]]
        let cloud = ["sync-id": [FavoriteQuestion(id: 7, title: "")]]
        let result = FavoriteTitleSync.adoptCloudTitles(
            merged: merged, cloud: cloud, uuidForSyncID: { _ in account },
            id: { $0.id }, title: \.title
        )
        #expect(result[account]?.map(\.title) == ["Two Sum"])
    }

    @Test
    func `cloud entries for unresolved accounts and unknown ids are ignored`() {
        let account = UUID()
        let merged = [account: [FavoritePad(id: "abc", title: "Kept")]]
        let cloud = [
            "unknown-account": [FavoritePad(id: "abc", title: "Other")],
            "sync-id": [FavoritePad(id: "zzz", title: "Unrelated")]
        ]
        let result = FavoriteTitleSync.adoptCloudTitles(
            merged: merged, cloud: cloud,
            uuidForSyncID: { $0 == "sync-id" ? account : nil },
            id: { $0.id }, title: \.title
        )
        #expect(result[account]?.map(\.title) == ["Kept"])
    }
}

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
