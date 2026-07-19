//
//  Accounts+PadOpened.swift
//  coderpad
//
//  Per-account pad-open tracking, split from Accounts+FavoritePads.swift to keep
//  that file within the file-length lint budget.
//

import Foundation
import os
import SwiftUI

/// Per-account record of when each pad was last opened, so the pad list can show
/// an activity dot on a started pad that has changed *since you last looked at it*
/// — a more personal signal than "changed since the last background refresh".
/// Scoped per account (a pad id only means something within its org) and
/// persisted to UserDefaults as a single JSON blob keyed by account id.
@Observable
final class PadOpenedStore {
    static let shared = PadOpenedStore()
    private var byAccount: [UUID: [String: Date]] = [:]
    /// Dated per-account deletion tombstones, so removing a deleted pad's record
    /// propagates through the most-recent-wins iCloud merge instead of the other
    /// Mac's mirror restoring it (#723).
    private var removedAt: [UUID: [String: Date]] = [:]
    private static let key = "padLastOpened.v1"
    private static let tombstonesKey = "padLastOpened.tombstones.v1"
    /// The iCloud mirror is keyed by each account's stable sync id, like the favourites
    /// mirror, so the activity-dot "last looked at" state follows the user across their
    /// Macs (#536).
    private static let cloudKey = "padLastOpened.cloud.v1"
    private static let cloudTombstonesKey = "padLastOpened.tombstones.cloud.v1"
    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? SharedCoders.decoder.decode([UUID: [String: Date]].self, from: data) {
            byAccount = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.tombstonesKey),
           let decoded = try? SharedCoders.decoder.decode([UUID: [String: Date]].self, from: data) {
            removedAt = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                // The tombstone blob changes independently of the history blob — a
                // pad deleted on another Mac writes only the former. Watching just the
                // history key meant that deletion was never reconciled here and the
                // deleted pad's activity state came back (#2605).
                let key = note.userInfo?["key"] as? String
                guard key == Self.cloudKey || key == Self.cloudTombstonesKey else { continue }

                Self.shared.syncFromCloud()
            }
        }
    }

    /// When the pad was last opened under this account, or `nil` if never opened.
    func lastOpened(_ padID: String, account: UUID?) -> Date? {
        guard let account else { return nil }

        return byAccount[account]?[padID]
    }

    /// Records that the pad was just opened, clearing its activity dot until it
    /// next changes. `now` is injectable for tests.
    func markOpened(_ padID: String, account: UUID, now: Date = Date()) {
        // An empty or whitespace-only id can never match a pad, so it would only
        // ever be dead weight in the persisted and mirrored blob (#2608).
        let id = padID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        // A detail view or navigation callback can land after its account has been
        // removed. Recording then recreates history for an account no UI can show
        // or clear, which teardown has already finished purging (#2607).
        guard AccountsStore.shared.accounts.contains(where: { $0.id == account }) else { return }

        byAccount[account, default: [:]][id] = now
        prune(account: account)
        save()
    }

    /// Pulls timestamps from a badly-set clock back to now.
    ///
    /// The merge keeps the greatest last-opened value per pad, so one device whose
    /// clock is set years ahead wins every subsequent open on every other device.
    /// The affected pads then look permanently already-read — their activity dot
    /// never returns — until real time catches up (#2610). A small tolerance
    /// absorbs ordinary clock skew between machines; beyond it, the value is not a
    /// time anyone actually opened a pad, so it is treated as now.
    static func clampingFutureDates(_ entries: [String: Date], now: Date = Date()) -> [String: Date] {
        let ceiling = now.addingTimeInterval(futureClockTolerance)
        guard entries.contains(where: { $0.value > ceiling }) else { return entries }

        return entries.mapValues { min($0, now) }
    }

    /// How far ahead of this device a timestamp may be before it is treated as a
    /// misconfigured clock rather than skew.
    static let futureClockTolerance: TimeInterval = 5 * 60

    /// Bounds one account's history to the most recently opened `maxEntriesPerAccount`.
    ///
    /// Nothing capped this: every pad ever opened stayed in UserDefaults and in the
    /// iCloud mirror forever, so in a busy organization the blob grew without limit
    /// (#2606). The activity dot only means anything for pads recent enough to still
    /// be in a list, so the oldest entries are the ones worth losing.
    private func prune(account: UUID) {
        guard let entries = byAccount[account], entries.count > Self.maxEntriesPerAccount else { return }

        let keep = entries
            .sorted { $0.value > $1.value }
            .prefix(Self.maxEntriesPerAccount)
        byAccount[account] = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }

    /// How many pad-open records are kept per account. Comfortably more than any
    /// list shows at once, so the dot is never wrong for a visible pad.
    static let maxEntriesPerAccount = 500

    /// How long a pad-open record is kept.
    ///
    /// Each record is a pad identifier plus the time you looked at it, held in
    /// UserDefaults and mirrored to iCloud. Only records for *deleted* pads were
    /// ever removed, so an identifier for every pad you ever opened persisted
    /// indefinitely (#2629). The activity dot is about recent change, so a record
    /// this old no longer informs anything.
    static let retention: TimeInterval = 90 * 24 * 60 * 60

    /// Drops every account's records for pads not opened within `retention`.
    /// Returns whether anything was removed.
    @discardableResult
    private func expireOldRecords(now: Date = Date()) -> Bool {
        let cutoff = now.addingTimeInterval(-Self.retention)
        var changed = false
        for (account, entries) in byAccount {
            let kept = entries.filter { $0.value >= cutoff }
            guard kept.count != entries.count else { continue }

            byAccount[account] = kept.isEmpty ? nil : kept
            changed = true
        }
        return changed
    }

    /// Forgets every pad-open record on this device and in the iCloud mirror.
    ///
    /// The activity dots reset — every started pad reads as changed until you open
    /// it again — which is the honest consequence of clearing the record of what
    /// you had looked at. Exposed so the history is not something a user can only
    /// wait out (#2629).
    func clearAllHistory() {
        guard !byAccount.isEmpty || !removedAt.isEmpty else { return }

        byAccount = [:]
        removedAt = [:]
        save()
    }

    /// Drops an account's open-history, called when the account is removed or
    /// re-keyed so its pad-open timestamps don't linger in UserDefaults (#379).
    func remove(account: UUID, syncID: String? = nil) {
        // Local removal alone left this account's records in the iCloud mirror, so
        // re-adding an account with the same stable sync identity merged its old
        // last-opened history straight back (#2611). Clearing the cloud side too
        // makes the removal mean what it says.
        if let syncID { removeFromCloud(syncID: syncID) }
        guard byAccount[account] != nil || removedAt[account] != nil else { return }

        byAccount[account] = nil
        removedAt[account] = nil
        save()
    }

    /// Deletes a removed account's entries from both mirrored cloud blobs, mirroring
    /// `FavoritesOrderStore.removeFromCloud` (#1150).
    private func removeFromCloud(syncID: String) {
        guard CloudSyncStore.shared.isAvailable else { return }

        for key in [Self.cloudKey, Self.cloudTombstonesKey] {
            guard let data = CloudSyncStore.shared.data(forKey: key),
                  var cloud = try? SharedCoders.decoder.decode([String: [String: Date]].self, from: data),
                  cloud.removeValue(forKey: syncID) != nil,
                  let updated = try? SharedCoders.encoder.encode(cloud)
            else { continue }

            CloudSyncStore.shared.mirror(updated, forKey: key)
        }
    }

    /// Drops one pad's open timestamp under `account`, called by the central
    /// deletion cleanup so a deleted pad's record doesn't persist indefinitely
    /// (and reattach if the same id is ever seen again, #723). Records a dated
    /// tombstone so the removal also propagates through the most-recent-wins
    /// cloud merge instead of another Mac restoring it.
    func removePad(_ padID: String, account: UUID) {
        // Tombstone unconditionally. Returning early when this device had no local
        // timestamp meant a pad whose open record lived only on another Mac — not
        // yet synced here — was deleted without any tombstone, so that record later
        // merged back in and resurrected the deleted pad's activity state (#2609).
        let hadRecord = byAccount[account]?[padID] != nil
        let alreadyTombstoned = removedAt[account]?[padID] != nil
        guard hadRecord || !alreadyTombstoned else { return }

        byAccount[account]?[padID] = nil
        removedAt[account, default: [:]][padID] = Date()
        save()
    }

    /// Reconciles one account after a complete authoritative list fetch. Records
    /// absent from that list represent pads removed outside this app; tombstoning
    /// them prevents a cloud mirror from restoring stale last-opened state (#1070).
    func reconcile(account: UUID, presentPadIDs: Set<String>, now: Date = Date()) {
        guard let entries = byAccount[account] else { return }

        let reconciled = Self.reconciledOpenRecords(entries, presentPadIDs: presentPadIDs)
        guard !reconciled.removedIDs.isEmpty else { return }

        byAccount[account] = reconciled.kept.isEmpty ? nil : reconciled.kept
        for padID in reconciled.removedIDs {
            removedAt[account, default: [:]][padID] = now
        }
        save()
    }

    static func reconciledOpenRecords(
        _ entries: [String: Date],
        presentPadIDs: Set<String>
    ) -> (kept: [String: Date], removedIDs: Set<String>) {
        let removedIDs = Set(entries.keys).subtracting(presentPadIDs)
        return (entries.filter { presentPadIDs.contains($0.key) }, removedIDs)
    }

    private func save() {
        // Records past the retention window go first, so neither the local blob nor
        // the mirror keeps identifiers for pads you looked at long ago (#2629).
        expireOldRecords()
        removedAt = Self.prunedTombstones(removedAt, liveRecords: byAccount)
        // Encode both blobs before writing either, and write the tombstones first.
        // Writing them one at a time could leave a record without its tombstone if
        // the second encode threw, and a record without its tombstone is exactly how
        // a deleted pad's activity state comes back (#2625). Tombstones-without-
        // records is the harmless direction: the deletion is still honoured.
        do {
            let history = try SharedCoders.encoder.encode(byAccount)
            let tombstones = try SharedCoders.encoder.encode(removedAt)
            UserDefaults.standard.set(tombstones, forKey: Self.tombstonesKey)
            UserDefaults.standard.set(history, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode pad open times: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Ages every account's tombstones independently of whether it still has live
    /// history, then retires tombstones for pads that were opened again (#1085).
    static func prunedTombstones(
        _ tombstones: [UUID: [String: Date]],
        liveRecords: [UUID: [String: Date]],
        now: Date = Date()
    ) -> [UUID: [String: Date]] {
        var result: [UUID: [String: Date]] = [:]
        for (account, entries) in tombstones {
            var kept = CloudTombstones.pruned(entries, now: now)
            for padID in liveRecords[account, default: [:]].keys {
                kept[padID] = nil
            }
            if !kept.isEmpty { result[account] = kept }
        }
        return result
    }

    /// Pushes the current open-history (and its deletion tombstones, #723) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        // Indexed once rather than scanned per account (#2439).
        let syncIDs = AccountsStore.shared.syncIDsByAccountID
        let syncID: (UUID) -> String? = { syncIDs[$0] }
        // Tombstones first, for the same reason as the local write above.
        mirror(CloudSyncMerge.toCloud(removedAt, syncID: syncID), forKey: Self.cloudTombstonesKey)
        mirror(CloudSyncMerge.toCloud(byAccount, syncID: syncID), forKey: Self.cloudKey)
    }

    /// Writes this device's contribution to a mirrored blob without disturbing the
    /// rest of it.
    ///
    /// The mirror is shared by every device, keyed by account sync id. Replacing it
    /// wholesale published only the accounts *this* device has configured — and
    /// `syncFromCloud` deliberately ignores identities it can't map — so a device
    /// that was missing an account, or had merely not finished loading its
    /// credentials, erased that account's history for every other device (#2628).
    /// Entries under identities this device doesn't know are carried through
    /// untouched.
    private func mirror(_ mine: [String: [String: Date]], forKey key: String) {
        var blob = mine
        if let data = CloudSyncStore.shared.data(forKey: key),
           let existing = try? SharedCoders.decoder.decode([String: [String: Date]].self, from: data) {
            for (identity, entries) in existing where mine[identity] == nil {
                blob[identity] = entries
            }
        }
        guard let data = try? SharedCoders.encoder.encode(blob) else { return }

        CloudSyncStore.shared.mirror(data, forKey: key)
    }

    /// Pulls the iCloud open-history and merges it into the local set, keeping the most
    /// recent open per pad, then resolves deletion tombstones (a deleted pad's record
    /// stays gone unless it was opened again after the deletion, #723), and persists.
    /// Called once accounts have loaded and on every external iCloud change. No-op
    /// when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? SharedCoders.decoder.decode([String: [String: Date]].self, from: data) else { return }

        let accountIDs = AccountsStore.shared.syncIdentityIndex.accountIDsBySyncID
        let uuidForSyncID: (String) -> UUID? = { accountIDs[$0] }
        var merged = CloudSyncMerge.mergeTimestamps(cloud: cloud, into: byAccount,
                                                    uuidForSyncID: uuidForSyncID)
        var tombstones = removedAt
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudTombstonesKey),
           let cloudTombstones = try? SharedCoders.decoder.decode([String: [String: Date]].self, from: data) {
            tombstones = CloudSyncMerge.mergeTimestamps(cloud: cloudTombstones, into: tombstones,
                                                        uuidForSyncID: uuidForSyncID)
        }
        for (account, entries) in merged {
            let resolved = CloudTombstones.resolveTimestamps(entries: entries,
                                                             tombstones: tombstones[account] ?? [:])
            merged[account] = Self.clampingFutureDates(resolved.entries)
            tombstones[account] = Self.clampingFutureDates(resolved.tombstones)
        }
        guard merged != byAccount || tombstones != removedAt else { return }

        byAccount = merged
        removedAt = tombstones
        save()
    }
}
