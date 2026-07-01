//
//  Accounts+Cache.swift
//  coderpad
//
//  Per-account list caches (pads, questions, organization, quota) with
//  stale-while-revalidate disk backing.
//

import Foundation
import os

/// App-side facade over ``DiskCache`` (in BuddyAppKit), pinning the cache directory
/// and logger. The implementation lives in the package so a sibling app can reuse it
/// with its own location; this layer keeps the call sites unchanged. Snapshots live in
/// Application Support, one JSON file per account+kind, so pads and questions a
/// returning user already loaded appear instantly on the next cold launch while the
/// network fetch refreshes them in the background (stale-while-revalidate). The static
/// methods stay `nonisolated` so reads/writes genuinely run off the main actor when
/// invoked from a detached task.
enum CacheDisk {
    private nonisolated static let cache = DiskCache(
        directoryName: "com.coderpad.app/DataCache",
        logger: Logger(subsystem: "com.coderpad.app", category: "cache")
    )

    nonisolated static func load<T: Decodable>(_ type: T.Type, kind: String, account: UUID) -> T? {
        cache.load(type, kind: kind, account: account)
    }

    nonisolated static func save(_ value: some Encodable, kind: String, account: UUID) {
        cache.save(value, kind: kind, account: account)
    }

    nonisolated static func delete(kind: String, account: UUID) {
        cache.delete(kind: kind, account: account)
    }

    nonisolated static func modificationDate(kind: String, account: UUID) -> Date? {
        cache.modificationDate(kind: kind, account: account)
    }
}

@Observable
final class PadsCacheStore {
    static let shared = PadsCacheStore()
    private(set) var padsByAccount: [UUID: [Pad]] = [:]
    /// Accounts whose disk snapshot we've already consulted, so a genuinely empty
    /// cache isn't re-read from disk on every `get`.
    private var diskConsulted: Set<UUID> = []
    private let writeQueue = SerialWriteQueue()
    private init() {}

    func get(_ accountID: UUID) -> [Pad] {
        if let cached = padsByAccount[accountID] { return cached }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Pad].self, kind: "pads", account: accountID) {
                padsByAccount[accountID] = disk
                return disk
            }
        }
        return []
    }

    /// `persist: false` updates only the in-memory snapshot, skipping the disk write —
    /// used when streaming pages so intermediate snapshots warm the UI without churning
    /// the disk; the caller persists once with the final, complete list.
    func set(_ accountID: UUID, pads: [Pad], persist: Bool = true) {
        padsByAccount[accountID] = pads
        diskConsulted.insert(accountID)
        guard persist else { return }

        // Index the complete list (not the streaming snapshots) when the user opted in.
        SpotlightIndexer.updatePads(pads, account: accountID)
        // Mirror every account's pads into the widget container (keyed by id) so a
        // configured widget can pin any account, updating the default snapshot for
        // whichever account is on screen.
        WidgetSync.refresh(pads: pads, account: accountID,
                           isCurrent: accountID == AccountsStore.shared.currentAccount?.id)
        // Reflect this account's active-pad count in the Dock badge (summed across
        // every account inside `refresh`), now that the complete list is in hand.
        DockBadgeController.refresh()
        writeQueue.enqueue {
            CacheDisk.save(pads, kind: "pads", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        padsByAccount[accountID] = nil
        diskConsulted.remove(accountID)
        writeQueue.enqueue {
            CacheDisk.delete(kind: "pads", account: accountID)
        }
        // Drop the account's mirrored widget snapshot and refresh the picker index.
        WidgetSync.removeAccount(accountID)
        // Removing an account drops its pads from the badge's all-accounts total.
        DockBadgeController.refresh()
    }

    /// Drop a single deleted pad from the cache so it stops appearing in Spotlight
    /// and the Recent Pads widget — re-indexing only adds/updates, so the deleted
    /// row needs an explicit removal. Finds the owning account by the (globally
    /// unique) pad id, then persists the reduced list.
    func removePad(id padID: String) {
        SpotlightIndexer.removePad(id: padID)
        for (accountID, pads) in padsByAccount where pads.contains(where: { $0.id == padID }) {
            let reduced = pads.filter { $0.id != padID }
            padsByAccount[accountID] = reduced
            WidgetSync.refresh(pads: reduced, account: accountID,
                               isCurrent: accountID == AccountsStore.shared.currentAccount?.id)
            writeQueue.enqueue {
                CacheDisk.save(reduced, kind: "pads", account: accountID)
            }
        }
        // A deleted pad may have been an active one, so re-derive the Dock badge.
        DockBadgeController.refresh()
    }
}

@Observable
final class QuestionsCacheStore {
    static let shared = QuestionsCacheStore()
    private(set) var questionsByAccount: [UUID: [Question]] = [:]
    private var diskConsulted: Set<UUID> = []
    private let writeQueue = SerialWriteQueue()
    private init() {}

    func get(_ accountID: UUID) -> [Question] {
        if let cached = questionsByAccount[accountID] { return cached }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Question].self, kind: "questions", account: accountID) {
                questionsByAccount[accountID] = disk
                return disk
            }
        }
        return []
    }

    func set(_ accountID: UUID, questions: [Question]) {
        questionsByAccount[accountID] = questions
        diskConsulted.insert(accountID)
        SpotlightIndexer.updateQuestions(questions, account: accountID)
        // Keep stored favourite titles current now that fresh questions (and their
        // titles) are in hand — this upgrades legacy id-only favourites and tracks
        // renames, so the sidebar never shows a "Question #id" placeholder (#325).
        FavoriteQuestionsStore.shared.refreshTitles(from: questions, account: accountID)
        // Refresh the widget's favourite-question titles for this account too.
        WidgetSync.syncFavorites(account: accountID)
        writeQueue.enqueue {
            CacheDisk.save(questions, kind: "questions", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        questionsByAccount[accountID] = nil
        diskConsulted.remove(accountID)
        writeQueue.enqueue {
            CacheDisk.delete(kind: "questions", account: accountID)
        }
    }

    /// Drop a single deleted question from the cache so it stops appearing in
    /// Spotlight — re-indexing only adds/updates, so the deleted row needs an
    /// explicit removal. Per-org ids aren't unique across accounts, so when the
    /// owning `account` is known only that account is touched; otherwise every
    /// account holding the id is updated (the prior, id-only behavior).
    func removeQuestion(id questionID: Int, account: UUID? = nil) {
        let targets = account.map { [$0] } ?? Array(questionsByAccount.keys)
        for accountID in targets {
            guard let questions = questionsByAccount[accountID],
                  questions.contains(where: { $0.id == questionID }) else { continue }

            // Spotlight identifiers are namespaced per account (#378), so remove
            // from the index inside the loop — once per account that holds the id.
            SpotlightIndexer.removeQuestion(id: questionID, account: accountID)
            let reduced = questions.filter { $0.id != questionID }
            questionsByAccount[accountID] = reduced
            writeQueue.enqueue {
                CacheDisk.save(reduced, kind: "questions", account: accountID)
            }
        }
    }
}

/// Holds the last-loaded organization per account so switching to the
/// Organization section shows it instantly while a background refresh runs,
/// instead of a blocking spinner every visit. `Organization` is `Decodable`
/// only, so this is memory-only (no disk persistence like pads/questions).
@Observable
final class OrganizationCacheStore {
    static let shared = OrganizationCacheStore()
    private(set) var byAccount: [UUID: Organization] = [:]

    /// Session cache + in-flight coalescing keyed by client identity (server + key),
    /// so the owner pickers, the new-pad sheet, and the org-name directory share one
    /// `/api/organization` fetch instead of each re-downloading the full teams + users
    /// payload (#374). Keyed by client rather than account because those callers hold
    /// only a `CoderPadClient`, not an account id. Memory-only, like `byAccount`.
    private var byClient: [String: Organization] = [:]
    private var inFlight: [String: Task<Organization, any Error>] = [:]

    private init() {}

    func get(_ accountID: UUID) -> Organization? {
        byAccount[accountID]
    }

    func set(_ accountID: UUID, organization: Organization) {
        byAccount[accountID] = organization
    }

    func remove(_ accountID: UUID) {
        byAccount[accountID] = nil
    }

    /// Fetch the organization for `client`, coalescing concurrent callers onto one
    /// request and serving a cached copy when one exists — stale-while-revalidate: a
    /// cached hit returns immediately and kicks off a background refresh. Only throws
    /// when there's no cached copy and the fetch fails (#374).
    func organization(via client: CoderPadClient) async throws -> Organization {
        let key = Self.clientKey(client)
        if let cached = byClient[key] {
            refreshInBackground(client, key: key)
            return cached
        }
        return try await fetch(client, key: key)
    }

    private func fetch(_ client: CoderPadClient, key: String) async throws -> Organization {
        // Coalesce: a concurrent caller for the same client awaits the same task rather
        // than starting a second identical request.
        if let existing = inFlight[key] { return try await existing.value }

        let task = Task { try await client.organization() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let org = try await task.value
        byClient[key] = org
        return org
    }

    private func refreshInBackground(_ client: CoderPadClient, key: String) {
        guard inFlight[key] == nil else { return }

        Task { _ = try? await fetch(client, key: key) }
    }

    private static func clientKey(_ client: CoderPadClient) -> String {
        "\(client.baseURL.absoluteString)|\(client.apiKey)"
    }
}

/// Holds the last-loaded events and environments per pad, so re-selecting a pad
/// the user already opened this session shows its detail instantly while a
/// background refresh runs, instead of a blocking spinner on every switch (#323).
/// Memory-only: this data is session-scoped and refreshed on every open, so —
/// like `OrganizationCacheStore` — there's no disk backing.
@Observable
final class PadDetailCacheStore {
    static let shared = PadDetailCacheStore()

    struct Entry {
        var events: [PadEvent]
        var environments: [PadEnvironment]
    }

    /// How many pads' detail payloads stay resident at once. Each entry holds a pad's
    /// full event log and all of its environments (which carry code-file contents), so
    /// an uncapped map grew without bound for the whole session — hundreds of KB per
    /// long pad (#421, a cause of #418). Keeping the most-recently-opened handful
    /// preserves the instant re-open behaviour (#323) while bounding memory, mirroring
    /// the count caps the other in-process caches already use.
    private static let limit = 12

    private(set) var byPad: [String: Entry] = [:]
    /// Pad ids in least- to most-recently-opened order, so an overflow evicts the
    /// least-recently-used entry. Bookkeeping only, so it stays out of observation.
    @ObservationIgnored private var lru: [String] = []
    private init() {}

    func get(_ padID: String) -> Entry? {
        byPad[padID]
    }

    func set(_ padID: String, events: [PadEvent], environments: [PadEnvironment]) {
        byPad[padID] = Entry(events: events, environments: environments)
        // Mark this pad most-recently-used, then evict the oldest while over the cap.
        // `set` runs on every open (load() refreshes), so set-order tracks open-order.
        lru.removeAll { $0 == padID }
        lru.append(padID)
        while lru.count > Self.limit {
            byPad[lru.removeFirst()] = nil
        }
    }

    // Deliberate cache-eviction API, kept for lifecycle symmetry.
    // periphery:ignore
    func remove(_ padID: String) {
        byPad[padID] = nil
        lru.removeAll { $0 == padID }
    }
}

/// Holds the last-loaded quota per account, for the same reason as
/// `OrganizationCacheStore`. Shared by both the Quota and Organization sections,
/// so visiting either one warms the other.
@Observable
final class QuotaCacheStore {
    static let shared = QuotaCacheStore()
    private(set) var byAccount: [UUID: Quota] = [:]
    private init() {}

    func get(_ accountID: UUID) -> Quota? {
        byAccount[accountID]
    }

    func set(_ accountID: UUID, quota: Quota) {
        byAccount[accountID] = quota
    }

    func remove(_ accountID: UUID) {
        byAccount[accountID] = nil
    }
}
