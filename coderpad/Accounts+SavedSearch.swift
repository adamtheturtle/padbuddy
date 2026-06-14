//
//  Accounts+SavedSearch.swift
//  coderpad
//
//  Per-account saved searches, favorite questions, and pad-open tracking.
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

    init(id: UUID = UUID(), name: String,
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
    func hasSameFilters(as other: NamedSearch) -> Bool {
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

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String: [NamedSearch]]].self, from: data) {
            byAccount = decoded
        }
        legacyPending = UserDefaults.standard.data(forKey: Self.legacyKey) != nil
        migrateLegacyIfNeeded()
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
    }
}

/// Per-account favorite ("starred") questions, identified by question id. A
/// favorite is a quick-access marker: starred questions float to the top of the
/// Questions list and lead the menu bar's "New Pad from Question" submenu, so a
/// frequently used question is one click away from a fresh pad. Scoped per
/// account — a question id only means something within the org that owns it — and
/// persisted to UserDefaults as a single JSON blob keyed by account id. The
/// stored array keeps insertion order so the menu bar can lead with the questions
/// the user starred first.
@Observable
final class FavoriteQuestionsStore {
    static let shared = FavoriteQuestionsStore()
    private var byAccount: [UUID: [Int]] = [:]
    private static let key = "favoriteQuestions.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [Int]].self, from: data) {
            byAccount = decoded
        }
    }

    func favorites(account: UUID?) -> [Int] {
        guard let account else { return [] }
        return byAccount[account] ?? []
    }

    func isFavorite(_ id: Int, account: UUID?) -> Bool {
        guard let account else { return false }
        return byAccount[account]?.contains(id) ?? false
    }

    /// Adds the question to favorites if absent, removes it if present. New
    /// favorites append to the end so the existing order is preserved.
    func toggle(_ id: Int, account: UUID) {
        var ids = byAccount[account] ?? []
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        byAccount[account] = ids
        save()
        // Keep the New Pad widget button's question picker in step with this account's
        // favourites.
        WidgetSync.syncFavorites(account: account)
    }

    /// Favorites the question if it isn't already, preserving order. Used by the
    /// sidebar drop target, where a drop should only ever add a favorite (never
    /// remove one), so a no-op when it's already starred.
    func add(_ id: Int, account: UUID) {
        var ids = byAccount[account] ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        byAccount[account] = ids
        save()
        WidgetSync.syncFavorites(account: account)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            let reason = error.localizedDescription
            persistenceLogger.error("Failed to encode favorite questions: \(reason, privacy: .public)")
        }
    }
}

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
