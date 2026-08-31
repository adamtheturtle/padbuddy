//
//  WidgetCompletedCreateLedger.swift
//  PadBuddy
//
//  The durable gate that stops one widget New Pad request creating two pads.
//

#if canImport(Darwin)
    import Darwin
#endif
import Foundation
import OSLog

/// Creating a pad is not idempotent, so a request that is drained twice — by two
/// activation paths, by a recovered claim, or by a second process — must create once.
///
/// The gate used to be a `shouldCreate` read and a `recordCompleted` write around an
/// `await`, with nothing in between: two drains could both see an id as absent, both
/// create, and only then both record (#4548). It is now a claim, taken under an
/// interprocess lock before the create starts and turned into a completion after, so the
/// window has no gap. `synchronize()` is gone with it: its return value was never proof
/// of durability, and a false one made a successful write look like a failure (#4549).
nonisolated enum WidgetCompletedCreateLedger {
    enum ClaimOutcome: Equatable {
        /// This process owns the create and must record its completion.
        case proceed
        /// A previous drain already created this pad.
        case alreadyCompleted
        /// Another drain is creating it right now.
        case inProgressElsewhere
        /// The ledger could not be read or written; the caller decides whether an
        /// unguarded create is better than none.
        case unavailable
    }

    enum LedgerError: Error {
        case containerUnavailable
        case lockUnavailable
        case ioFailure
    }

    /// Entries must outlive every transport artifact that could still replay a request.
    /// Evicting purely by count let an old but still-recoverable request come back and
    /// create a duplicate pad (#4550), so retention is tied to the mailbox's message
    /// lifetime instead, with the count cap only as a backstop against unbounded growth.
    static var retentionLifetime: TimeInterval {
        WidgetSharedStore.legacyRequestLifetime * 2
    }

    static let maximumEntries = 4096

    /// How long a claim may sit before a later drain assumes the claiming process died.
    static var abandonedClaimLifetime: TimeInterval {
        WidgetSharedStore.abandonedClaimLifetime
    }

    static let fileName = "widget-completed-new-pad-requests.json"

    private static let logger = Logger(subsystem: "com.coderpad.app", category: "widget-create-ledger")

    enum EntryState: String, Codable {
        case claimed
        case completed
    }

    struct Entry: Codable, Equatable {
        var state: EntryState
        var recordedAt: Double
    }

    /// Takes the create for `id` if nothing else holds or has finished it.
    static func claim(
        _ id: UUID,
        now: Date = Date(),
        containerURL: URL? = nil
    ) -> ClaimOutcome {
        guard let directory = containerURL ?? WidgetSharedStore.containerURL(purpose: "widget create ledger") else {
            return .unavailable
        }

        do {
            return try withLock(in: directory) {
                var entries = try load(in: directory)
                if let existing = entries[id.uuidString] {
                    switch existing.state {
                    case .completed:
                        return .alreadyCompleted

                    case .claimed:
                        let age = now.timeIntervalSinceReferenceDate - existing.recordedAt
                        guard age > abandonedClaimLifetime else { return .inProgressElsewhere }

                        logger.notice("Recovering an abandoned widget New Pad claim \(id, privacy: .public)")
                    }
                }
                entries[id.uuidString] = Entry(state: .claimed, recordedAt: now.timeIntervalSinceReferenceDate)
                try store(prune(entries, now: now), in: directory)
                return .proceed
            }
        } catch {
            logger.error("Could not claim a widget New Pad request: \(error.localizedDescription, privacy: .public)")
            return .unavailable
        }
    }

    /// Turns this process's claim into a completion. Throws on a real write failure, so a
    /// caller can tell "not persisted" from "persisted but `synchronize` said false".
    static func recordCompleted(_ id: UUID, now: Date = Date(), containerURL: URL? = nil) throws {
        guard let directory = containerURL ?? WidgetSharedStore.containerURL(purpose: "widget create ledger") else {
            throw LedgerError.containerUnavailable
        }

        try withLock(in: directory) {
            var entries = try load(in: directory)
            entries[id.uuidString] = Entry(state: .completed, recordedAt: now.timeIntervalSinceReferenceDate)
            try store(prune(entries, now: now), in: directory)
        }
    }

    /// Drops a claim whose create did not happen, so the request is retried promptly
    /// rather than waiting out the abandoned-claim window.
    static func releaseClaim(_ id: UUID, now: Date = Date(), containerURL: URL? = nil) {
        guard let directory = containerURL ?? WidgetSharedStore.containerURL(purpose: "widget create ledger") else {
            return
        }

        do {
            try withLock(in: directory) {
                var entries = try load(in: directory)
                guard entries[id.uuidString]?.state == .claimed else { return }

                entries[id.uuidString] = nil
                try store(prune(entries, now: now), in: directory)
            }
        } catch {
            logger.error("Could not release a widget New Pad claim: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func entries(in directory: URL) -> [String: Entry] {
        (try? withLock(in: directory) { try load(in: directory) }) ?? [:]
    }

    // MARK: - Storage

    private static func prune(_ entries: [String: Entry], now: Date) -> [String: Entry] {
        let cutoff = now.timeIntervalSinceReferenceDate - retentionLifetime
        var kept = entries.filter { $0.value.recordedAt >= cutoff }
        guard kept.count > maximumEntries else { return kept }

        // Past the backstop the retention guarantee cannot be honoured for everything, so
        // say so rather than silently making old requests replayable again.
        logger.error("Widget create ledger exceeded \(maximumEntries) entries; evicting inside the retention window")
        for key in kept.sorted(by: { $0.value.recordedAt < $1.value.recordedAt })
            .prefix(kept.count - maximumEntries).map(\.key) {
            kept[key] = nil
        }
        return kept
    }

    private static func load(in directory: URL) throws -> [String: Entry] {
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: Entry].self, from: data)
        } catch {
            // A corrupt or temporarily unreadable ledger must not be treated as
            // "nothing was ever created": that would make every recoverable request
            // replayable. Keep the file for diagnosis and refuse to claim until it can
            // be read or is deliberately replaced.
            logger.error("Widget create ledger is unreadable: \(error.localizedDescription, privacy: .public)")
            throw LedgerError.ioFailure
        }
    }

    private static func store(_ entries: [String: Entry], in directory: URL) throws {
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        do {
            try JSONEncoder().encode(entries).write(to: url, options: [.atomic])
        } catch {
            logger.error("Could not write the widget create ledger: \(error.localizedDescription, privacy: .public)")
            throw LedgerError.ioFailure
        }
    }

    /// An exclusive advisory lock on a sibling file, so claim-then-write is atomic against
    /// the widget extension and a second app instance, not just against another task here.
    private static func withLock<T>(in directory: URL, _ body: () throws -> T) throws -> T {
        let lockURL = directory.appending(path: "\(fileName).lock", directoryHint: .notDirectory)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw LedgerError.lockUnavailable }

        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw LedgerError.lockUnavailable }

        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
