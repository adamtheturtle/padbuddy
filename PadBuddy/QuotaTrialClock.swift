//
//  QuotaTrialClock.swift
//  coderpad
//

import Foundation

nonisolated enum QuotaTrialClock {
    static func waitUntilExpiration(
        _ expiration: Date,
        now: Date = Date(),
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws {
        let delay = expiration.timeIntervalSince(now)
        guard delay > 0 else { return }

        try await sleep(.seconds(delay))
    }
}
