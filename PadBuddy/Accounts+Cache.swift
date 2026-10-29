//
//  Accounts+Cache.swift
//  coderpad
//
//  Per-account list caches (pads, questions, organization, quota) with
//  stale-while-revalidate disk backing.
//

// swiftlint:disable file_length

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
        let existed = cache.modificationDate(kind: kind, account: account) != nil
        let value = cache.load(type, kind: kind, account: account)
        if value != nil {
            CacheLoadDiagnostics.clear(kind: kind, account: account)
        } else if existed {
            CacheLoadDiagnostics.recordFailure(kind: kind, account: account)
        }
        return value
    }

    nonisolated static func save(_ value: some Codable, kind: String, account: UUID) {
        cache.save(value, kind: kind, account: account)
    }

    @discardableResult
    nonisolated static func delete(kind: String, account: UUID) -> Bool {
        let existed = cache.modificationDate(kind: kind, account: account) != nil
        cache.delete(kind: kind, account: account)
        CacheLoadDiagnostics.clear(kind: kind, account: account)
        return existed
    }

    nonisolated static func modificationDate(kind: String, account: UUID) -> Date? {
        cache.modificationDate(kind: kind, account: account)
    }

    /// Total bytes occupied by this account's JSON snapshots (#3288).
    nonisolated static func diskUsage(account: UUID) -> Int64? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first else { return nil }

        let directory = support.appending(path: cache.directoryName, directoryHint: .isDirectory)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let suffix = "-\(account.uuidString).json"
        return files.lazy
            .filter { $0.lastPathComponent.hasSuffix(suffix) }
            .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(0) { $0 + Int64($1) }
    }
}

@Observable
final class PadsCacheStore {
    static let shared = PadsCacheStore()
    private(set) var padsByAccount: [UUID: [Pad]] = [:]
    private(set) var recentPadsByAccount: [UUID: [Pad]] = [:]
    /// Bumped on every per-account write, so a background warm can tell whether a
    /// fresher writer (a user-initiated reload) touched the account since it last
    /// wrote — a slow prefetch started first must not complete last and replace
    /// the fresher result (#1242).
    private(set) var writeGeneration: [UUID: Int] = [:]
    /// Accounts whose disk snapshot we've already consulted, so a genuinely empty
    /// cache isn't re-read from disk on every `get`.
    private var diskConsulted: Set<UUID> = []
    private var diskPrewarming: Set<UUID> = []

    /// Whether this account's snapshot has been read from disk yet. Cleanup that resolves
    /// an account-less broadcast against the cached lists needs to tell "no account holds
    /// this" from "the caches are still warming" (#4609).
    func hasConsultedDisk(_ accountID: UUID) -> Bool {
        diskConsulted.contains(accountID)
    }

    func isPrewarming(_ accountID: UUID) -> Bool {
        diskPrewarming.contains(accountID)
    }

    private let writeQueue = SerialWriteQueue()
    private let persistenceEpochs = CachePersistenceEpochs()
    private var loadGenerations: [UUID: Int] = [:]
    private init() {}

    func cached(_ accountID: UUID) -> [Pad] {
        padsByAccount[accountID] ?? []
    }

    func recent(_ accountID: UUID) -> [Pad] {
        _ = get(accountID)
        return recentPadsByAccount[accountID] ?? []
    }

    func get(_ accountID: UUID) -> [Pad] {
        if let cached = padsByAccount[accountID] {
            return cached
        }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load(
                BoundedDecodedArray<Pad, CacheRecordLimit>.self, kind: "pads", account: accountID
            )?.values {
                let normalized = Self.normalizedDiskPads(disk)
                padsByAccount[accountID] = normalized
                recentPadsByAccount[accountID] = Self.mostRecent(normalized)
                return normalized
            }
        }
        return []
    }

    /// Warms the in-memory snapshot from disk off the main actor, so the first
    /// list render after launch finds memory already populated instead of doing
    /// a large JSON read/decode inside `body` (#1769). `get`'s synchronous disk
    /// fallback remains for accounts added mid-session.
    func prewarm(_ accountID: UUID) {
        guard padsByAccount[accountID] == nil,
              !diskConsulted.contains(accountID),
              diskPrewarming.insert(accountID).inserted
        else { return }

        Task {
            let disk = await Task.detached(priority: .utility) {
                CacheDisk.load(
                    BoundedDecodedArray<Pad, CacheRecordLimit>.self, kind: "pads", account: accountID
                )?.values
            }.value
            diskPrewarming.remove(accountID)
            // A load or removal that landed meanwhile wins over the prewarm.
            guard padsByAccount[accountID] == nil, !diskConsulted.contains(accountID) else { return }

            diskConsulted.insert(accountID)
            if let disk {
                let normalized = Self.normalizedDiskPads(disk)
                padsByAccount[accountID] = normalized
                recentPadsByAccount[accountID] = Self.mostRecent(normalized)
                DockBadgeController.refresh()
            }
        }
    }

    /// Disk snapshots are disposable and may come from an older/crashed writer.
    /// Keep the first occurrence to preserve the stored order while guaranteeing
    /// stable SwiftUI/cache identity before publication (#1438).
    static func normalizedDiskPads(_ pads: [Pad]) -> [Pad] {
        var seen = Set<String>()
        var result: [Pad] = []
        for pad in pads.prefix(CacheRecordLimit.maximumElements) {
            guard let id = MergedPadIdentity.validated(pad.id), seen.insert(id).inserted else { continue }

            result.append(pad)
        }
        return result
    }

    static func mostRecent(_ pads: [Pad], limit: Int = 10) -> [Pad] {
        guard limit > 0 else { return [] }

        var result: [Pad] = []
        result.reserveCapacity(min(limit, pads.count))
        for pad in pads {
            let date = pad.updatedAt ?? pad.createdAt ?? .distantPast
            let insertion = result.firstIndex {
                date > ($0.updatedAt ?? $0.createdAt ?? .distantPast)
            } ?? result.endIndex
            result.insert(pad, at: insertion)
            if result.count > limit {
                result.removeLast()
            }
        }
        return result
    }

    /// `persist: false` updates only the in-memory snapshot, skipping the disk write —
    /// used when streaming pages so intermediate snapshots warm the UI without churning
    /// the disk; the caller persists once with the final, complete list.
    ///
    /// `client` is the client the pads were fetched through: a load can outlive the
    /// removal or re-key of its account, and caching its late result would resurrect
    /// data teardown just purged — into memory, disk, Spotlight, the widget, and the
    /// Dock badge (#754). Results whose credentials no longer match the account are
    /// dropped.
    func beginLoad(_ accountID: UUID, via client: CoderPadClient) -> Int? {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return nil }

        loadGenerations[accountID, default: 0] &+= 1
        return loadGenerations[accountID]
    }

    func set(
        _ accountID: UUID, pads: [Pad], via client: CoderPadClient,
        persist: Bool = true, accepting loadGeneration: Int? = nil
    ) {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return }

        if let loadGeneration {
            guard loadGenerations[accountID] == loadGeneration else { return }
        } else {
            loadGenerations[accountID, default: 0] &+= 1
        }

        // Apply the same stable-identity normalization used for disk hydration
        // before publishing a live snapshot or any of its side effects. Paginated
        // endpoints can overlap at a page boundary and return an id twice (#5132).
        let pads = Self.normalizedDiskPads(pads)
        padsByAccount[accountID] = pads
        recentPadsByAccount[accountID] = Self.mostRecent(pads)
        writeGeneration[accountID, default: 0] += 1
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
        // Keep stored favourite-pad titles current now that fresh pads (and their
        // titles) are in hand — tracks renames and names a pad favourited while
        // still untitled, so the sidebar shows a current title (#654).
        FavoritePadsStore.shared.refreshTitles(from: pads, account: accountID)
        let persistenceEpoch = persistenceEpochs.advance(for: accountID)
        let epochStore = persistenceEpochs
        writeQueue.enqueue {
            guard epochStore.isCurrent(persistenceEpoch, for: accountID) else { return }

            CacheDisk.save(pads, kind: "pads", account: accountID)
        }
    }

    /// Insert a just-created pad at the top of `account`'s cached list, so
    /// Spotlight, the widget, the Dock badge, and any list mounting later see it
    /// immediately instead of waiting for the next full reload (#1251). A no-op
    /// when the pad is already cached, so a duplicated create broadcast can't
    /// produce a duplicate row (#1218).
    func insertPad(_ pad: Pad, account accountID: UUID, via client: CoderPadClient) {
        // Hydrate a persisted snapshot when one exists, but do not turn "no
        // authoritative list yet" into a complete one-row list. An empty array in
        // `padsByAccount` is meaningful: a completed fetch proved the list empty.
        // An absent entry after `get` means there was no live or disk snapshot to
        // patch, so the next mounted surface must perform a full fetch (#5131).
        _ = get(accountID)
        guard let pads = padsByAccount[accountID] else { return }
        guard !pads.contains(where: { $0.id == pad.id }) else { return }

        set(accountID, pads: [pad] + pads, via: client)
    }

    /// Drops a list snapshot after a successful out-of-band mutation (the MCP
    /// server), forcing the next reader to obtain authoritative server state.
    func invalidateSnapshot(_ accountID: UUID) {
        loadGenerations[accountID, default: 0] &+= 1
        let stale = padsByAccount.removeValue(forKey: accountID) ?? []
        recentPadsByAccount[accountID] = nil
        writeGeneration[accountID, default: 0] += 1
        diskConsulted.insert(accountID)
        let persistenceEpoch = persistenceEpochs.advance(for: accountID)
        let epochStore = persistenceEpochs
        writeQueue.enqueue {
            guard epochStore.isCurrent(persistenceEpoch, for: accountID) else { return }

            CacheDisk.delete(kind: "pads", account: accountID)
        }
        for pad in stale {
            SpotlightIndexer.removePad(id: pad.id, account: accountID)
        }
        WidgetSync.refresh(pads: [], account: accountID,
                           isCurrent: accountID == AccountsStore.shared.currentAccount?.id)
        DockBadgeController.refresh()
    }

    /// `isRekey: true` drops the widget snapshot without tombstoning the account:
    /// a re-keyed account persists, so the removal tombstone (never cleared for a
    /// still-present account) would silently block every future widget refresh and
    /// leave the widget blank until an unrelated account-list change (#1022).
    func remove(_ accountID: UUID, isRekey: Bool = false) {
        loadGenerations[accountID, default: 0] &+= 1
        padsByAccount[accountID] = nil
        recentPadsByAccount[accountID] = nil
        // Mark the disk snapshot as consulted rather than forgetting it: the file
        // deletion below runs asynchronously on the write queue, and an unmarked
        // account would let any `get` in that window rehydrate the just-purged
        // snapshot from disk back into memory (#755). The file is gone afterwards,
        // so a re-added account with the same id starts empty either way.
        diskConsulted.insert(accountID)
        let persistenceEpoch = persistenceEpochs.advance(for: accountID)
        let epochStore = persistenceEpochs
        writeQueue.enqueue {
            guard epochStore.isCurrent(persistenceEpoch, for: accountID) else { return }

            CacheDisk.delete(kind: "pads", account: accountID)
        }
        // Drop the account's mirrored widget snapshot and refresh the picker index.
        let wasCurrent = accountID == AccountsStore.shared.currentAccount?.id
        if isRekey {
            WidgetSync.clearAccount(accountID, isCurrent: wasCurrent)
        } else {
            WidgetSync.removeAccount(
                accountID,
                remainingAccounts: AccountsStore.shared.accounts.filter { $0.id != accountID },
                wasCurrent: wasCurrent
            )
        }
        // Removing an account drops its pads from the badge's all-accounts total.
        DockBadgeController.refresh()
    }
}

@Observable
final class QuestionsCacheStore {
    static let shared = QuestionsCacheStore()
    private(set) var questionsByAccount: [UUID: [Question]] = [:]
    /// See ``PadsCacheStore/writeGeneration`` (#1242).
    private(set) var writeGeneration: [UUID: Int] = [:]
    private var diskConsulted: Set<UUID> = []
    private var diskPrewarming: Set<UUID> = []

    /// Whether this account's snapshot has been read from disk yet. Cleanup that resolves
    /// an account-less broadcast against the cached lists needs to tell "no account holds
    /// this" from "the caches are still warming" (#4609).
    func hasConsultedDisk(_ accountID: UUID) -> Bool {
        diskConsulted.contains(accountID)
    }

    func isPrewarming(_ accountID: UUID) -> Bool {
        diskPrewarming.contains(accountID)
    }

    private let writeQueue = SerialWriteQueue()
    private let persistenceEpochs = CachePersistenceEpochs()
    private var loadGenerations: [UUID: Int] = [:]
    private init() {}

    func cached(_ accountID: UUID) -> [Question] {
        questionsByAccount[accountID] ?? []
    }

    /// Whether this account has an authoritative live or persisted list snapshot.
    /// A completed empty fetch is still a snapshot and can safely accept a
    /// single-question mutation; absence means a patch would masquerade as the
    /// account's complete question bank (#5130).
    func hasListSnapshot(_ accountID: UUID) -> Bool {
        _ = get(accountID)
        return questionsByAccount[accountID] != nil
    }

    func get(_ accountID: UUID) -> [Question] {
        if let cached = questionsByAccount[accountID] {
            return cached
        }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Question].self, kind: "questions", account: accountID) {
                let normalized = Self.normalizedDiskQuestions(disk)
                questionsByAccount[accountID] = normalized
                return normalized
            }
        }
        return []
    }

    /// Warms the in-memory snapshot from disk off the main actor; see
    /// ``PadsCacheStore/prewarm(_:)`` (#1769).
    func prewarm(_ accountID: UUID) {
        guard questionsByAccount[accountID] == nil,
              !diskConsulted.contains(accountID),
              diskPrewarming.insert(accountID).inserted
        else { return }

        Task {
            let disk = await Task.detached(priority: .utility) {
                CacheDisk.load([Question].self, kind: "questions", account: accountID)
            }.value
            diskPrewarming.remove(accountID)
            guard questionsByAccount[accountID] == nil, !diskConsulted.contains(accountID) else { return }

            diskConsulted.insert(accountID)
            if let disk {
                questionsByAccount[accountID] = Self.normalizedDiskQuestions(disk)
            }
        }
    }

    /// Preserve the first valid row and ordering, but never publish non-positive or
    /// duplicate question identities into lists or mutation paths (#1439, #5133).
    static func normalizedDiskQuestions(_ questions: [Question]) -> [Question] {
        var seen: Set<Int> = []
        return questions.filter { $0.id > 0 && seen.insert($0.id).inserted }
    }

    /// `persist: false` updates only the in-memory snapshot, skipping disk, Spotlight,
    /// favorites, and widget side effects. Used while streaming pages so a canceled view
    /// load still leaves warm rows for a quick section switch back.
    ///
    /// `client` is the client the questions were fetched through; results whose
    /// credentials no longer match the account are dropped, so a load that outlived
    /// its account's removal or re-key can't resurrect purged data (#754).
    /// Claims ordering for a network load before it begins. Only the newest claim for
    /// an account may publish, even when every load uses identical credentials (#1441).
    func beginLoad(_ accountID: UUID, via client: CoderPadClient) -> Int? {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return nil }

        loadGenerations[accountID, default: 0] &+= 1
        return loadGenerations[accountID]
    }

    func set(
        _ accountID: UUID, questions: [Question], via client: CoderPadClient,
        persist: Bool = true, accepting loadGeneration: Int? = nil
    ) {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return }

        if let loadGeneration {
            guard loadGenerations[accountID] == loadGeneration else { return }
        } else {
            // A direct mutation is newer than every in-flight fetch.
            loadGenerations[accountID, default: 0] &+= 1
        }

        let questions = Self.normalizedDiskQuestions(questions)
        questionsByAccount[accountID] = questions
        writeGeneration[accountID, default: 0] += 1
        diskConsulted.insert(accountID)
        guard persist else { return }

        SpotlightIndexer.updateQuestions(questions, account: accountID)
        // Keep stored favourite titles current now that fresh questions (and their
        // titles) are in hand — this upgrades legacy id-only favourites and tracks
        // renames, so the sidebar never shows a "Question #id" placeholder (#325).
        FavoriteQuestionsStore.shared.refreshTitles(from: questions, account: accountID)
        // Refresh the widget's favourite-question titles for this account too.
        WidgetSync.syncFavorites(account: accountID)
        let persistenceEpoch = persistenceEpochs.advance(for: accountID)
        let epochStore = persistenceEpochs
        writeQueue.enqueue {
            guard epochStore.isCurrent(persistenceEpoch, for: accountID) else { return }

            CacheDisk.save(questions, kind: "questions", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        loadGenerations[accountID, default: 0] &+= 1
        questionsByAccount[accountID] = nil
        // Consulted, not forgotten: see PadsCacheStore.remove — an unmarked account
        // could rehydrate the purged snapshot from disk before the queued file
        // deletion runs (#755).
        diskConsulted.insert(accountID)
        let persistenceEpoch = persistenceEpochs.advance(for: accountID)
        let epochStore = persistenceEpochs
        writeQueue.enqueue {
            guard epochStore.isCurrent(persistenceEpoch, for: accountID) else { return }

            CacheDisk.delete(kind: "questions", account: accountID)
        }
    }

    /// Question counterpart to ``PadsCacheStore/invalidateSnapshot(_:)``.
    func invalidateSnapshot(_ accountID: UUID) {
        loadGenerations[accountID, default: 0] &+= 1
        let stale = questionsByAccount.removeValue(forKey: accountID) ?? []
        writeGeneration[accountID, default: 0] += 1
        diskConsulted.insert(accountID)
        let persistenceEpoch = persistenceEpochs.advance(for: accountID)
        let epochStore = persistenceEpochs
        writeQueue.enqueue {
            guard epochStore.isCurrent(persistenceEpoch, for: accountID) else { return }

            CacheDisk.delete(kind: "questions", account: accountID)
        }
        for question in stale {
            SpotlightIndexer.removeQuestion(id: question.id, account: accountID)
        }
    }
}

// PadDetailCacheStore (the per-pad detail cache) lives in
// Accounts+Cache+PadDetail.swift, QuotaCacheStore in Accounts+Cache+Quota.swift, and
// OrganizationCacheStore in Accounts+Cache+Organization.swift, all split out for
// file length.
