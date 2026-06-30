//
//  FavoritesOrder.swift
//  coderpad
//
//  The single drag order that favourite pads and starred questions share in the
//  sidebar. Membership and titles still live in FavoritePadsStore and
//  FavoriteQuestionsStore; this records only the order the two kinds interleave in.
//

import Foundation
import os
import SwiftUI

/// One sidebar favourite, regardless of kind, so a pad and a starred question can sit
/// in one drag-ordered list. The associated value is the kind's own identifier — a pad
/// slug or a per-org question id — matching the id each kind-specific store uses.
enum FavoriteRef: Codable, Hashable, Sendable {
    case pad(String)
    case question(Int)
}

/// The interleaved drag order of a sidebar's favourites — pads and starred questions in
/// one list — per account. Before this, the sidebar always listed every favourite pad
/// above every favourite question; now a single order spans both kinds so a question can
/// be dragged between two pads and stay there.
///
/// Membership stays in the two kind-specific stores (``FavoritePadsStore`` /
/// ``FavoriteQuestionsStore``); this records only the combined order, reconciled against
/// current membership on every read (see ``order(present:account:)``) so a newly
/// favourited item appends and an un-favourited one drops without bookkeeping at each
/// add/remove site. With no saved order yet, the reconciliation simply yields the
/// `present` order it's handed — pads then questions — so a first run matches the old
/// layout exactly and no migration is needed.
///
/// Persisted to UserDefaults as one JSON blob keyed by account id and mirrored to iCloud
/// keyed by each account's stable sync id, like the favourites themselves (#536).
@Observable
final class FavoritesOrderStore {
    static let shared = FavoritesOrderStore()
    private var byAccount: [UUID: [FavoriteRef]] = [:]
    private static let key = "favoritesOrder.v1"
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    private static let cloudKey = "favoritesOrder.cloud.v1"
    /// Held so the external-change observation task isn't cancelled; the store is a
    /// singleton that lives for the whole process, so it's never explicitly stopped.
    private var cloudObserverTask: Task<Void, Never>?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [FavoriteRef]].self, from: data) {
            byAccount = decoded
        }
        // Re-pull and merge whenever iCloud reports an external change to our mirror.
        cloudObserverTask = Task { @MainActor in
            for await note in NotificationCenter.default.notifications(named: CloudSyncStore.didChangeExternally) {
                guard note.userInfo?["key"] as? String == Self.cloudKey else { continue }

                Self.shared.syncFromCloud()
            }
        }
    }

    /// The favourites for `account` in their stored drag order, reconciled against the
    /// `present` membership: stored refs that are still favourites keep their saved
    /// position, then any present ref not yet in the stored order is appended in
    /// `present` order (a just-added favourite lands at the end). Pure — it doesn't
    /// persist — so the order stays derivable from `present` until a drag rewrites it.
    func order(present: [FavoriteRef], account: UUID?) -> [FavoriteRef] {
        guard let account else { return present }

        let presentSet = Set(present)
        var result = (byAccount[account] ?? []).filter { presentSet.contains($0) }
        let have = Set(result)
        result.append(contentsOf: present.filter { !have.contains($0) })
        return result
    }

    /// Moves `ref` to sit immediately before `target` in the combined order and persists
    /// the result, seeding from the reconciled `present` order so the saved blob captures
    /// any not-yet-recorded favourites too (drag-to-reorder in the sidebar, #299). A no-op
    /// if either ref is absent or they're the same.
    func move(_ ref: FavoriteRef, before target: FavoriteRef, present: [FavoriteRef], account: UUID) {
        guard ref != target else { return }

        var ordered = order(present: present, account: account)
        guard let from = ordered.firstIndex(of: ref), ordered.contains(target) else { return }

        ordered.remove(at: from)
        let insertAt = ordered.firstIndex(of: target) ?? ordered.count
        ordered.insert(ref, at: insertAt)
        byAccount[account] = ordered
        save()
    }

    /// Drops an account's saved order, called when the account is removed or re-keyed so
    /// its favourite refs don't linger in UserDefaults, alongside the kind-specific
    /// stores (#379).
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
            persistenceLogger.error("Failed to encode favorites order: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current order up to iCloud, keyed by each account's stable sync id.
    /// No-op when iCloud is unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let cloud = CloudSyncMerge.toCloud(byAccount) { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud order and merges it into the local set (union per account,
    /// keeping local positions and appending cloud-only refs), then persists. Called once
    /// accounts have loaded and on every external iCloud change. Reconciliation on read
    /// still drops any ref that isn't an actual favourite, so a stale ref can't surface.
    /// No-op when iCloud is unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [FavoriteRef]].self, from: data) else { return }

        let merged = CloudSyncMerge.mergeArrays(cloud: cloud, into: byAccount) { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        }
        guard merged != byAccount else { return }

        byAccount = merged
        save()
    }
}
