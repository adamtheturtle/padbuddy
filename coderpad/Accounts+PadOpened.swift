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
           let decoded = try? JSONDecoder().decode([UUID: [String: Date]].self, from: data) {
            byAccount = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.tombstonesKey),
           let decoded = try? JSONDecoder().decode([UUID: [String: Date]].self, from: data) {
            removedAt = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                guard note.userInfo?["key"] as? String == Self.cloudKey else { continue }

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
        byAccount[account, default: [:]][padID] = now
        save()
    }

    /// Drops an account's open-history, called when the account is removed or
    /// re-keyed so its pad-open timestamps don't linger in UserDefaults (#379).
    func remove(account: UUID) {
        guard byAccount[account] != nil || removedAt[account] != nil else { return }

        byAccount[account] = nil
        removedAt[account] = nil
        save()
    }

    /// Drops one pad's open timestamp under `account`, called by the central
    /// deletion cleanup so a deleted pad's record doesn't persist indefinitely
    /// (and reattach if the same id is ever seen again, #723). Records a dated
    /// tombstone so the removal also propagates through the most-recent-wins
    /// cloud merge instead of another Mac restoring it.
    func removePad(_ padID: String, account: UUID) {
        guard byAccount[account]?[padID] != nil else { return }

        byAccount[account]?[padID] = nil
        removedAt[account, default: [:]][padID] = Date()
        save()
    }

    private func save() {
        // A present pad retires its tombstone (opened again after a deletion), and
        // old tombstones age out so the map stays bounded.
        for (account, entries) in byAccount {
            guard var tombstones = removedAt[account] else { continue }

            for padID in entries.keys {
                tombstones[padID] = nil
            }
            removedAt[account] = CloudTombstones.pruned(tombstones)
        }
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
            let tombstones = try JSONEncoder().encode(removedAt)
            UserDefaults.standard.set(tombstones, forKey: Self.tombstonesKey)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode pad open times: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current open-history (and its deletion tombstones, #723) up to
    /// iCloud, keyed by each account's stable sync id. No-op when iCloud is
    /// unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let syncID: (UUID) -> String? = { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(CloudSyncMerge.toCloud(byAccount, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
        if let data = try? JSONEncoder().encode(CloudSyncMerge.toCloud(removedAt, syncID: syncID)) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudTombstonesKey)
        }
    }

    /// Pulls the iCloud open-history and merges it into the local set, keeping the most
    /// recent open per pad, then resolves deletion tombstones (a deleted pad's record
    /// stays gone unless it was opened again after the deletion, #723), and persists.
    /// Called once accounts have loaded and on every external iCloud change. No-op
    /// when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [String: Date]].self, from: data) else { return }

        let uuidForSyncID: (String) -> UUID? = { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
        var merged = CloudSyncMerge.mergeTimestamps(cloud: cloud, into: byAccount,
                                                    uuidForSyncID: uuidForSyncID)
        var tombstones = removedAt
        if let data = CloudSyncStore.shared.data(forKey: Self.cloudTombstonesKey),
           let cloudTombstones = try? JSONDecoder().decode([String: [String: Date]].self, from: data) {
            tombstones = CloudSyncMerge.mergeTimestamps(cloud: cloudTombstones, into: tombstones,
                                                        uuidForSyncID: uuidForSyncID)
        }
        for (account, entries) in merged {
            let resolved = CloudTombstones.resolveTimestamps(entries: entries,
                                                             tombstones: tombstones[account] ?? [:])
            merged[account] = resolved.entries
            tombstones[account] = resolved.tombstones
        }
        guard merged != byAccount || tombstones != removedAt else { return }

        byAccount = merged
        removedAt = tombstones
        save()
    }
}
