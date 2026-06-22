//
//  Accounts+FavoritePads.swift
//  coderpad
//
//  Per-account favorite pads and pad-open tracking.
//

import Foundation
import os
import SwiftUI

/// Per-account favorite ("pinned") pads, identified by pad id. The pad counterpart
/// to ``FavoriteQuestionsStore``: dragging a pad onto the sidebar pins it as a
/// quick-access shortcut. Scoped per account — a pad id is a CoderPad slug, unique
/// across orgs, but favorites are still kept per account so the sidebar shows the
/// right set — and persisted to UserDefaults as one JSON blob keyed by account id.
/// The array keeps insertion order so the sidebar lists pads in the order pinned.
@Observable
final class FavoritePadsStore {
    static let shared = FavoritePadsStore()
    private var byAccount: [UUID: [String]] = [:]
    private static let key = "favoritePads.v1"
    /// The iCloud mirror is keyed by each account's stable sync id (a `String`), not
    /// the per-device `UUID` the local blob uses, so it lives under its own key with
    /// its own schema (#536).
    private static let cloudKey = "favoritePads.cloud.v1"
    /// Held so the external-change observer isn't discarded; the store is a singleton
    /// that lives for the whole process, so it's never explicitly removed.
    private var cloudObserver: (any NSObjectProtocol)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String]].self, from: data) {
            byAccount = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudSyncStore.didChangeExternally, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            // Delivered on the main queue, so we're already on the main actor.
            MainActor.assumeIsolated {
                guard key == Self.cloudKey else { return }

                Self.shared.syncFromCloud()
            }
        }
    }

    func favorites(account: UUID?) -> [String] {
        guard let account else { return [] }

        return byAccount[account] ?? []
    }

    func isFavorite(_ id: String, account: UUID?) -> Bool {
        guard let account else { return false }

        return byAccount[account]?.contains(id) ?? false
    }

    /// Pins the pad if it isn't already, preserving order. Used by the sidebar drop
    /// target, where a drop should only ever add (never remove) a favorite.
    func add(_ id: String, account: UUID) {
        var ids = byAccount[account] ?? []
        guard !ids.contains(id) else { return }

        ids.append(id)
        byAccount[account] = ids
        save()
    }

    /// Toggles the pad's pinned state, appending when newly pinned so order holds.
    func toggle(_ id: String, account: UUID) {
        var ids = byAccount[account] ?? []
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        byAccount[account] = ids
        save()
    }

    func remove(_ id: String, account: UUID) {
        guard var ids = byAccount[account], let index = ids.firstIndex(of: id) else { return }

        ids.remove(at: index)
        byAccount[account] = ids
        save()
    }

    /// Reorders `id` to sit immediately before `targetID`, persisting the new order
    /// (drag-to-reorder in the sidebar, #299). A no-op if either id isn't present.
    func move(_ id: String, before targetID: String, account: UUID) {
        var ids = byAccount[account] ?? []
        guard let from = ids.firstIndex(of: id), ids.contains(targetID), id != targetID else { return }

        ids.remove(at: from)
        let insertAt = ids.firstIndex(of: targetID) ?? ids.count
        ids.insert(id, at: insertAt)
        byAccount[account] = ids
        save()
    }

    /// Drops every favorite for an account, called when the account is removed or
    /// re-keyed so its pinned pad ids don't linger in UserDefaults (#379).
    func remove(account: UUID) {
        guard byAccount[account] != nil else { return }

        byAccount[account] = nil
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite pads: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current favourites up to iCloud, keyed by each account's stable sync
    /// id. No-op when iCloud is unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let cloud = AccountSyncMerge.toCloud(byAccount) { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud favourites and merges them into the local set (additive union
    /// per account), then persists. Called once accounts have loaded and on every
    /// external iCloud change. No-op when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }

        let merged = AccountSyncMerge.mergeArrays(cloud: cloud, into: byAccount) { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
        guard merged != byAccount else { return }

        byAccount = merged
        save()
    }
}

/// Per-account record of when each pad was last opened, so the pad list can show
/// an activity dot on a started pad that has changed *since you last looked at it*
/// — a more personal signal than "changed since the last background refresh".
/// Scoped per account (a pad id only means something within its org) and
/// persisted to UserDefaults as a single JSON blob keyed by account id.
@Observable
final class PadOpenedStore {
    static let shared = PadOpenedStore()
    private var byAccount: [UUID: [String: Date]] = [:]
    private static let key = "padLastOpened.v1"
    /// The iCloud mirror is keyed by each account's stable sync id, like the favourites
    /// mirror, so the activity-dot "last looked at" state follows the user across their
    /// Macs (#536).
    private static let cloudKey = "padLastOpened.cloud.v1"
    /// Held so the external-change observer isn't discarded; the store is a singleton
    /// that lives for the whole process, so it's never explicitly removed.
    private var cloudObserver: (any NSObjectProtocol)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String: Date]].self, from: data) {
            byAccount = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserver = NotificationCenter.default.addObserver(
            forName: CloudSyncStore.didChangeExternally, object: nil, queue: .main
        ) { note in
            let key = note.userInfo?["key"] as? String
            // Delivered on the main queue, so we're already on the main actor.
            MainActor.assumeIsolated {
                guard key == Self.cloudKey else { return }

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
        guard byAccount[account] != nil else { return }

        byAccount[account] = nil
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode pad open times: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current open-history up to iCloud, keyed by each account's stable sync
    /// id. No-op when iCloud is unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let cloud = AccountSyncMerge.toCloud(byAccount) { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud open-history and merges it into the local set, keeping the most
    /// recent open per pad, then persists. Called once accounts have loaded and on every
    /// external iCloud change. No-op when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [String: Date]].self, from: data) else { return }

        let merged = AccountSyncMerge.mergeTimestamps(cloud: cloud, into: byAccount) { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
        guard merged != byAccount else { return }

        byAccount = merged
        save()
    }
}
