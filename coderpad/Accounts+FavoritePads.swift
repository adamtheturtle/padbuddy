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

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String]].self, from: data) {
            byAccount = decoded
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

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite pads: \(reason, privacy: .public)")
        }
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

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String: Date]].self, from: data) {
            byAccount = decoded
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

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode pad open times: \(reason, privacy: .public)")
        }
    }
}
