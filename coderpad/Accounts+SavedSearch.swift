//
//  Accounts+SavedSearch.swift
//  coderpad
//
//  Per-account saved searches. Favorite questions live in
//  Accounts+FavoriteQuestions.swift; pad-open tracking in Accounts+FavoritePads.swift.
//

import Foundation
import os
import SwiftUI

/// A saved filter+search snapshot. The fields are a superset across the pad and
/// question lists — pads use state/team/dateRange, questions use draft — so one
/// shape serves both. Unused fields stay `nil` for a given kind, and all are
/// optional so snapshots saved before a field existed still decode.
struct NamedSearch: Identifiable, Codable, Hashable {
    /// The longest a saved-search name may be. Names are short recall labels shown
    /// as chips, so capping them keeps any one chip from dominating the bar and
    /// guards against an accidental paste of a huge string. Enforced as the user
    /// types and again on save; chips also clamp display so names persisted before
    /// the cap existed stay bounded.
    static let maxNameLength = 40

    let id: UUID
    var name: String
    var search: String
    var stateFilter: PadState?
    var languageFilter: String?
    var ownerFilter: String?
    var teamFilter: String?
    var typeFilter: String?
    /// Independent date constraints for the pad list: one applied to the updated
    /// date, one to the created date. Nil when the search has no such constraint.
    /// Optional so snapshots saved before these existed still decode.
    var updatedWindow: PadDateWindow?
    var createdWindow: PadDateWindow?
    var draftFilter: String?

    init(name: String,
         id: UUID = UUID(),
         search: String = "",
         stateFilter: PadState? = nil, languageFilter: String? = nil,
         ownerFilter: String? = nil, teamFilter: String? = nil,
         typeFilter: String? = nil,
         updatedWindow: PadDateWindow? = nil, createdWindow: PadDateWindow? = nil,
         draftFilter: String? = nil) {
        self.id = id
        self.name = name
        self.search = search
        self.stateFilter = stateFilter
        self.languageFilter = languageFilter
        self.ownerFilter = ownerFilter
        self.teamFilter = teamFilter
        self.typeFilter = typeFilter
        self.updatedWindow = updatedWindow
        self.createdWindow = createdWindow
        self.draftFilter = draftFilter
    }

    /// A plain-language list of the active filters, suitable for feeding to the
    /// on-device namer. The name itself is intentionally left out — that's what
    /// we're generating. Empty when nothing but a name is set, so callers can skip
    /// naming a search that has no distinguishing criteria to summarize.
    var filterDescription: String {
        var parts: [String] = []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("text contains \"\(query)\"") }
        if let stateFilter { parts.append("state is \(stateFilter.rawValue)") }
        if let languageFilter { parts.append("language is \(languageFilter)") }
        if let ownerFilter { parts.append("owner is \(ownerFilter)") }
        if let teamFilter { parts.append("team is \(teamFilter)") }
        if let typeFilter { parts.append("type is \(typeFilter)") }
        appendWindowDescription(updatedWindow, noun: "updated", to: &parts)
        appendWindowDescription(createdWindow, noun: "created", to: &parts)
        if let draftFilter { parts.append("draft status is \(draftFilter)") }
        return parts.joined(separator: ", ")
    }

    private func appendWindowDescription(_ window: PadDateWindow?, noun: String, to parts: inout [String]) {
        guard let window, window.isActive else { return }

        if window.customStart != nil || window.customEnd != nil {
            parts.append("\(noun) within a custom date range")
        } else if let range = window.range {
            parts.append("\(noun) date range is \(range)")
        }
    }

    /// Whether two searches carry the same filter criteria, ignoring `id` and
    /// `name`. A live filter signature can be matched against a saved or built-in
    /// search regardless of how it was labeled, so the in-list chips and the
    /// sidebar share one definition of "this search is currently applied" and can
    /// never drift. Fields a given list doesn't use stay nil on both sides, so the
    /// full-field comparison is correct for both pads and questions.
    func hasSameFilters(as other: Self) -> Bool {
        search == other.search &&
            stateFilter == other.stateFilter &&
            languageFilter == other.languageFilter &&
            ownerFilter == other.ownerFilter &&
            teamFilter == other.teamFilter &&
            typeFilter == other.typeFilter &&
            updatedWindow == other.updatedWindow &&
            createdWindow == other.createdWindow &&
            draftFilter == other.draftFilter
    }
}

/// Which list a saved search belongs to. Pads and questions have distinct filter
/// sets, so their saved searches are kept in separate buckets even though they
/// share the `NamedSearch` shape.
enum SavedSearchKind: String, Codable, Hashable {
    case pads
    case questions
}

/// Per-account saved searches for the pad and question lists. Searches are scoped
/// to the account that created them — owners, teams, and languages are all
/// account-specific, so a search saved against one org is meaningless in another —
/// and further partitioned by list kind. Persisted to UserDefaults as a single
/// JSON blob keyed by account id then kind; the encoder/decoder pair is symmetric,
/// so the nested dictionaries round-trip faithfully.
@Observable
final class SavedSearchStore {
    static let shared = SavedSearchStore()
    private var byAccount: [UUID: [String: [NamedSearch]]] = [:]
    /// True while a legacy `v1` blob is still on disk waiting to be folded in. The
    /// migration needs a current account, which may not exist yet at init, so we
    /// retry on each mutation until it succeeds.
    private var legacyPending = false
    private static let key = "savedSearches.v2"
    private static let legacyKey = "savedPadSearches.v1"
    /// The iCloud mirror, keyed by each account's stable sync id rather than the
    /// per-device `UUID`, under its own key (#536).
    private static let cloudKey = "savedSearches.cloud.v1"
    private var cloudObserver: (any NSObjectProtocol)?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String: [NamedSearch]]].self, from: data) {
            byAccount = decoded
        }
        legacyPending = UserDefaults.standard.data(forKey: Self.legacyKey) != nil
        migrateLegacyIfNeeded()
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

    func searches(account: UUID?, kind: SavedSearchKind) -> [NamedSearch] {
        guard let account else { return [] }

        return byAccount[account]?[kind.rawValue] ?? []
    }

    func add(_ search: NamedSearch, account: UUID, kind: SavedSearchKind) {
        migrateLegacyIfNeeded()
        byAccount[account, default: [:]][kind.rawValue, default: []].append(search)
        save()
    }

    func remove(id: UUID, account: UUID, kind: SavedSearchKind) {
        migrateLegacyIfNeeded()
        byAccount[account]?[kind.rawValue]?.removeAll { $0.id == id }
        save()
    }

    /// Drops every saved search (both kinds) for an account, called when the
    /// account is removed or re-keyed so its search definitions don't linger in
    /// UserDefaults (#379).
    func remove(account: UUID) {
        guard byAccount[account] != nil else { return }

        byAccount[account] = nil
        save()
    }

    /// Carries pre-existing global pad searches (saved before searches became
    /// per-account) into the current account's pad bucket, so upgrading doesn't
    /// silently drop them. Folds the legacy searches in alongside any existing
    /// `v2` pad bucket rather than overwriting it, and leaves the legacy blob in
    /// place to retry later if no account is current yet.
    private func migrateLegacyIfNeeded() {
        guard legacyPending else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.legacyKey),
              let legacy = try? JSONDecoder().decode([NamedSearch].self, from: data)
        else {
            legacyPending = false
            return
        }

        // No account to attribute the searches to yet — keep the blob and retry on
        // the next mutation (or next launch) once an account exists.
        guard let account = AccountsStore.shared.currentAccountID else { return }

        if !legacy.isEmpty {
            byAccount[account, default: [:]][SavedSearchKind.pads.rawValue, default: []]
                .insert(contentsOf: legacy, at: 0)
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        legacyPending = false
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode saved searches: \(reason, privacy: .public)")
        }
        mirrorToCloud()
    }

    /// Pushes the current saved searches up to iCloud, keyed by each account's stable
    /// sync id. No-op when iCloud is unavailable (#536).
    private func mirrorToCloud() {
        guard CloudSyncStore.shared.isAvailable else { return }

        let cloud = AccountSyncMerge.toCloud(byAccount) { uuid in
            AccountsStore.shared.accounts.first { $0.id == uuid }?.syncID
        }
        if let data = try? JSONEncoder().encode(cloud) {
            CloudSyncStore.shared.mirror(data, forKey: Self.cloudKey)
        }
    }

    /// Pulls the iCloud saved searches and merges them in, unioning each (account, kind)
    /// bucket by search id so a search renamed on one device never forks. Called once
    /// accounts have loaded and on every external iCloud change. No-op when iCloud is
    /// unavailable (#536).
    func syncFromCloud() {
        guard let data = CloudSyncStore.shared.data(forKey: Self.cloudKey),
              let cloud = try? JSONDecoder().decode([String: [String: [NamedSearch]]].self, from: data)
        else { return }

        let merged = AccountSyncMerge.mergeNestedArrays(cloud: cloud, into: byAccount) { identity in
            AccountsStore.shared.accounts.first { $0.syncID == identity }?.id
        } id: { $0.id }
        guard merged != byAccount else { return }

        byAccount = merged
        save()
    }
}
