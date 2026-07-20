//
//  CachePersistenceEpochs.swift
//  coderpad
//

import Foundation
import os

/// Thread-safe lifecycle tokens for detached cache writes. A queued job may touch
/// disk only while its token is still the newest operation for that account.
final nonisolated class CachePersistenceEpochs: Sendable {
    private let values = OSAllocatedUnfairLock<[UUID: UInt64]>(initialState: [:])

    func advance(for account: UUID) -> UInt64 {
        values.withLock { values in
            let next = (values[account] ?? 0) &+ 1
            values[account] = next
            return next
        }
    }

    func isCurrent(_ epoch: UInt64, for account: UUID) -> Bool {
        values.withLock { $0[account] == epoch }
    }
}
