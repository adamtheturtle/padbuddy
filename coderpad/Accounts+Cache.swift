//
//  Accounts+Cache.swift
//  coderpad
//
//  Per-account list caches (pads, questions, organization, quota) with
//  stale-while-revalidate disk backing.
//

import Foundation
import os

/// On-disk backing for the per-account list caches. Lets pads and questions a
/// returning user already loaded appear instantly on the next cold launch, with
/// the network fetch refreshing them in the background (stale-while-revalidate).
///
/// Snapshots live in Application Support, one JSON file per account+kind. The
/// encoder/decoder pair is symmetric (default strategies), so it round-trips the
/// API models faithfully without depending on the API's date format.
enum CacheDisk {
    /// nonisolated so reads/writes genuinely run off the main actor when invoked
    /// from a detached task, rather than hopping back to the main thread.
    private nonisolated static let logger = Logger(subsystem: "com.coderpad.app", category: "cache")

    private nonisolated static func url(kind: String, account: UUID) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appending(path: "com.coderpad.app/DataCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(kind)-\(account.uuidString).json")
    }

    nonisolated static func load<T: Decodable>(_: T.Type, kind: String, account: UUID) -> T? {
        guard let url = url(kind: kind, account: account),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to decode \(kind, privacy: .public) cache: \(reason, privacy: .public)")
            return nil
        }
    }

    nonisolated static func save(_ value: some Encodable, kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to write \(kind, privacy: .public) cache: \(reason, privacy: .public)")
        }
    }

    nonisolated static func delete(kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }
        try? FileManager.default.removeItem(at: url)
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
        // Keep the Recent Pads widget in step with the account that's on screen.
        if accountID == AccountsStore.shared.currentAccount?.id {
            WidgetSync.refresh(pads: pads)
        }
        // Reflect this account's active-pad count in the Dock badge (summed across
        // every account inside `refresh`), now that the complete list is in hand.
        DockBadge.refresh()
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
        // Removing an account drops its pads from the badge's all-accounts total.
        DockBadge.refresh()
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
            if accountID == AccountsStore.shared.currentAccount?.id {
                WidgetSync.refresh(pads: reduced)
            }
            writeQueue.enqueue {
                CacheDisk.save(reduced, kind: "pads", account: accountID)
            }
        }
        // A deleted pad may have been an active one, so re-derive the Dock badge.
        DockBadge.refresh()
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
        SpotlightIndexer.removeQuestion(id: questionID)
        let targets = account.map { [$0] } ?? Array(questionsByAccount.keys)
        for accountID in targets {
            guard let questions = questionsByAccount[accountID],
                  questions.contains(where: { $0.id == questionID }) else { continue }
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
