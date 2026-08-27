//
//  CacheLoadDiagnostics.swift
//  coderpad
//

import Foundation
import os

/// Records only failed reads of files that actually existed. Missing snapshots are a
/// normal cold-cache state; an existing file that cannot be read or decoded is useful
/// recovery information for Account Settings (#3070).
nonisolated enum CacheLoadDiagnostics {
    /// The snapshot kinds ``CacheDisk`` reads, and so the only values this state can ever
    /// hold. `kind` reaches here as a string because it doubles as a cache filename, and
    /// an unrecognised one would otherwise be retained for the life of the process and
    /// shown to the user as a failure they have no way to act on (#4545).
    enum Kind: String, CaseIterable {
        case pads
        case questions
        case directory
    }

    private static let failures = OSAllocatedUnfairLock(initialState: [UUID: Set<Kind>]())
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "cache")

    static func recordFailure(kind: String, account: UUID) {
        guard let kind = Kind(rawValue: kind) else {
            logger.error("Ignoring cache load failure for unknown kind \(kind, privacy: .public)")
            return
        }

        _ = failures.withLock { $0[account, default: []].insert(kind) }
    }

    static func clear(kind: String, account: UUID) {
        guard let kind = Kind(rawValue: kind) else { return }

        failures.withLock { failures in
            failures[account]?.remove(kind)
            if failures[account]?.isEmpty == true {
                failures[account] = nil
            }
        }
    }

    /// Drops everything recorded for an account. Removal and re-key cleanup does not know
    /// which kinds happened to fail, so without this the account's UUID and its stale
    /// failure strings were retained for the rest of the process — and an id reused by
    /// restoration or a test would inherit an unrelated account's failures (#4545).
    static func clear(account: UUID) {
        failures.withLock { $0[account] = nil }
    }

    static func failedKinds(account: UUID) -> [String] {
        failures.withLock { ($0[account] ?? []).map(\.rawValue).sorted() }
    }
}
