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

    nonisolated static func load<T: Codable>(_ type: T.Type, kind: String, account: UUID) -> T? {
        cache.load(type, kind: kind, account: account)
    }

    nonisolated static func save(_ value: some Codable, kind: String, account: UUID) {
        cache.save(value, kind: kind, account: account)
    }

    @discardableResult
    nonisolated static func delete(kind: String, account: UUID) -> Bool {
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
    /// Bumped on every per-account write, so a background warm can tell whether a
    /// fresher writer (a user-initiated reload) touched the account since it last
    /// wrote — a slow prefetch started first must not complete last and replace
    /// the fresher result (#1242).
    private(set) var writeGeneration: [UUID: Int] = [:]
    /// Accounts whose disk snapshot we've already consulted, so a genuinely empty
    /// cache isn't re-read from disk on every `get`.
    private var diskConsulted: Set<UUID> = []
    private let writeQueue = SerialWriteQueue()
    private let persistenceEpochs = CachePersistenceEpochs()
    private init() {}

    func cached(_ accountID: UUID) -> [Pad] {
        padsByAccount[accountID] ?? []
    }

    func get(_ accountID: UUID) -> [Pad] {
        if let cached = padsByAccount[accountID] { return cached }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Pad].self, kind: "pads", account: accountID) {
                let normalized = Self.normalizedDiskPads(disk)
                padsByAccount[accountID] = normalized
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
        guard padsByAccount[accountID] == nil, !diskConsulted.contains(accountID) else { return }

        Task {
            let disk = await Task.detached(priority: .utility) {
                CacheDisk.load([Pad].self, kind: "pads", account: accountID)
            }.value
            // A load or removal that landed meanwhile wins over the prewarm.
            guard padsByAccount[accountID] == nil, !diskConsulted.contains(accountID) else { return }

            diskConsulted.insert(accountID)
            if let disk { padsByAccount[accountID] = Self.normalizedDiskPads(disk) }
        }
    }

    /// Disk snapshots are disposable and may come from an older/crashed writer.
    /// Keep the first occurrence to preserve the stored order while guaranteeing
    /// stable SwiftUI/cache identity before publication (#1438).
    static func normalizedDiskPads(_ pads: [Pad]) -> [Pad] {
        var seen: Set<String> = []
        return pads.filter { seen.insert($0.id).inserted }
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
    func set(_ accountID: UUID, pads: [Pad], via client: CoderPadClient, persist: Bool = true) {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return }

        padsByAccount[accountID] = pads
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
        writeQueue.enqueue(coalescingKey: "pads.\(accountID.uuidString)") {
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
        let pads = get(accountID)
        guard !pads.contains(where: { $0.id == pad.id }) else { return }

        set(accountID, pads: [pad] + pads, via: client)
    }

    /// `isRekey: true` drops the widget snapshot without tombstoning the account:
    /// a re-keyed account persists, so the removal tombstone (never cleared for a
    /// still-present account) would silently block every future widget refresh and
    /// leave the widget blank until an unrelated account-list change (#1022).
    func remove(_ accountID: UUID, isRekey: Bool = false) {
        padsByAccount[accountID] = nil
        // Mark the disk snapshot as consulted rather than forgetting it: the file
        // deletion below runs asynchronously on the write queue, and an unmarked
        // account would let any `get` in that window rehydrate the just-purged
        // snapshot from disk back into memory (#755). The file is gone afterwards,
        // so a re-added account with the same id starts empty either way.
        diskConsulted.insert(accountID)
        let persistenceEpoch = persistenceEpochs.advance(for: accountID)
        let epochStore = persistenceEpochs
        writeQueue.enqueue(coalescingKey: "pads.\(accountID.uuidString)") {
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

    /// Drop a single deleted pad from the cache so it stops appearing in Spotlight
    /// and the Recent Pads widget — re-indexing only adds/updates, so the deleted
    /// row needs an explicit removal. Slugs are unique on the hosted service but
    /// can collide across custom servers, so when the owning `account` is known
    /// only that account is touched; otherwise every account holding the slug is
    /// updated (the prior, id-only behavior) (#761). Warms each account from disk
    /// via `get` rather than scanning only the in-memory lists: deletion cleanup
    /// exists precisely for the cold-cache case (#721), and gating on residency
    /// left the widget snapshot and disk cache stale (#1032). Accounts already
    /// consulted resolve from memory, so the warm-cache path is unchanged.
    func removePad(id padID: String, account: UUID? = nil) {
        if let account {
            SpotlightIndexer.removePad(id: padID, account: account)
        } else {
            SpotlightIndexer.removePad(id: padID)
        }
        let knownAccounts = account.map { [$0] }
            ?? Array(Set(AccountsStore.shared.accounts.map(\.id)).union(padsByAccount.keys))
        for accountID in knownAccounts {
            // `cached` for the id-only sweep, `get` when the caller named an account —
            // see the matching note in `removeQuestion` (#2448).
            let pads = account == nil ? cached(accountID) : get(accountID)
            guard pads.contains(where: { $0.id == padID }) else { continue }

            let reduced = pads.filter { $0.id != padID }
            padsByAccount[accountID] = reduced
            writeGeneration[accountID, default: 0] += 1
            WidgetSync.refresh(pads: reduced, account: accountID,
                               isCurrent: accountID == AccountsStore.shared.currentAccount?.id)
            let persistenceEpoch = persistenceEpochs.advance(for: accountID)
            let epochStore = persistenceEpochs
            writeQueue.enqueue(coalescingKey: "pads.\(accountID.uuidString)") {
                guard epochStore.isCurrent(persistenceEpoch, for: accountID) else { return }

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
    /// See ``PadsCacheStore/writeGeneration`` (#1242).
    private(set) var writeGeneration: [UUID: Int] = [:]
    private var diskConsulted: Set<UUID> = []
    private let writeQueue = SerialWriteQueue()
    private init() {}

    func cached(_ accountID: UUID) -> [Question] {
        questionsByAccount[accountID] ?? []
    }

    func get(_ accountID: UUID) -> [Question] {
        if let cached = questionsByAccount[accountID] { return cached }
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
        guard questionsByAccount[accountID] == nil, !diskConsulted.contains(accountID) else { return }

        Task {
            let disk = await Task.detached(priority: .utility) {
                CacheDisk.load([Question].self, kind: "questions", account: accountID)
            }.value
            guard questionsByAccount[accountID] == nil, !diskConsulted.contains(accountID) else { return }

            diskConsulted.insert(accountID)
            if let disk { questionsByAccount[accountID] = Self.normalizedDiskQuestions(disk) }
        }
    }

    /// Mirrors pad hydration: preserve the first stored row and ordering, but never
    /// publish duplicate question identities into lists or mutation paths (#1439).
    static func normalizedDiskQuestions(_ questions: [Question]) -> [Question] {
        var seen: Set<Int> = []
        return questions.filter { seen.insert($0.id).inserted }
    }

    /// `persist: false` updates only the in-memory snapshot, skipping disk, Spotlight,
    /// favorites, and widget side effects. Used while streaming pages so a canceled view
    /// load still leaves warm rows for a quick section switch back.
    ///
    /// `client` is the client the questions were fetched through; results whose
    /// credentials no longer match the account are dropped, so a load that outlived
    /// its account's removal or re-key can't resurrect purged data (#754).
    func set(_ accountID: UUID, questions: [Question], via client: CoderPadClient, persist: Bool = true) {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return }

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
        writeQueue.enqueue(coalescingKey: "questions.\(accountID.uuidString)") {
            CacheDisk.save(questions, kind: "questions", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        questionsByAccount[accountID] = nil
        // Consulted, not forgotten: see PadsCacheStore.remove — an unmarked account
        // could rehydrate the purged snapshot from disk before the queued file
        // deletion runs (#755).
        diskConsulted.insert(accountID)
        writeQueue.enqueue(coalescingKey: "questions.\(accountID.uuidString)") {
            CacheDisk.delete(kind: "questions", account: accountID)
        }
    }

    /// Drop a single deleted question from the cache so it stops appearing in
    /// Spotlight — re-indexing only adds/updates, so the deleted row needs an
    /// explicit removal. Per-org ids aren't unique across accounts, so when the
    /// owning `account` is known only that account is touched; otherwise every
    /// account holding the id is updated (the prior, id-only behavior).
    ///
    /// Warms each target account from disk via `get` rather than gating on the
    /// in-memory list: deletion cleanup exists precisely for the cold-cache case
    /// (#721), and skipping cold accounts left Spotlight and the disk cache stale
    /// (#1032). Spotlight persists independently of the list cache, so when the
    /// owning account is known its index entry is cleared unconditionally; the
    /// id-only sweep keeps the containment gate because per-org ids collide
    /// across accounts.
    func removeQuestion(id questionID: Int, account: UUID? = nil) {
        let targets = account.map { [$0] }
            ?? Array(Set(AccountsStore.shared.accounts.map(\.id)).union(questionsByAccount.keys))
        for accountID in targets {
            // `cached` for the id-only sweep: `get` falls back to a synchronous
            // whole-file read and decode per account on the main actor, and an account
            // whose list isn't in memory can't be displaying this question anywhere
            // that needs correcting (#2448). An explicitly-targeted account still gets
            // the full read, since the caller knows which list it means.
            let questions = account == nil ? cached(accountID) : get(accountID)
            let holdsQuestion = questions.contains { $0.id == questionID }
            // Spotlight identifiers are namespaced per account (#378), so remove
            // from the index inside the loop — once per account that holds the id.
            if account != nil || holdsQuestion {
                SpotlightIndexer.removeQuestion(id: questionID, account: accountID)
            }
            guard holdsQuestion else { continue }

            let reduced = questions.filter { $0.id != questionID }
            questionsByAccount[accountID] = reduced
            writeGeneration[accountID, default: 0] += 1
            writeQueue.enqueue(coalescingKey: "questions.\(accountID.uuidString)") {
                CacheDisk.save(reduced, kind: "questions", account: accountID)
            }
        }
    }
}

// PadDetailCacheStore (the per-pad detail cache) lives in
// Accounts+Cache+PadDetail.swift, QuotaCacheStore in Accounts+Cache+Quota.swift, and
// OrganizationCacheStore in Accounts+Cache+Organization.swift, all split out for
// file length.
