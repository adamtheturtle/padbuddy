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
    private static let failures = OSAllocatedUnfairLock(initialState: [UUID: Set<String>]())

    static func recordFailure(kind: String, account: UUID) {
        _ = failures.withLock { $0[account, default: []].insert(kind) }
    }

    static func clear(kind: String, account: UUID) {
        failures.withLock { failures in
            failures[account]?.remove(kind)
            if failures[account]?.isEmpty == true {
                failures[account] = nil
            }
        }
    }

    static func failedKinds(account: UUID) -> [String] {
        failures.withLock { ($0[account] ?? []).sorted() }
    }
}
