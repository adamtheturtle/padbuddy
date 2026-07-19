//
//  Accounts+BackgroundRefreshFailures.swift
//  coderpad
//
//  Safe diagnostics and retry policy for background pad refresh failures.
//

import Foundation
import os

extension PadsBackgroundRefresher {
    func recordFailure(
        accountID: UUID,
        clientIdentity: ClientTaskIdentity,
        kind: FailureKind
    ) {
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == accountID }),
              account.makeClient().taskIdentity == clientIdentity else { return }

        let previous = failuresByAccount[accountID]
        let count = previous?.clientIdentity == clientIdentity ? previous?.consecutiveFailures ?? 0 : 0
        let consecutiveFailures = count + 1
        let now = Date()
        failuresByAccount[accountID] = FailureState(
            clientIdentity: clientIdentity,
            kind: kind,
            consecutiveFailures: consecutiveFailures,
            lastFailure: now,
            retryAfter: now.addingTimeInterval(Self.retryDelay(for: consecutiveFailures))
        )
        let logger = Logger(subsystem: "com.coderpad.app", category: "background-refresh")
        logger.error("""
        Background pad refresh failed for account \(accountID, privacy: .public): \
        \(kind.rawValue, privacy: .public)
        """)
    }

    nonisolated static func retryDelay(for consecutiveFailures: Int) -> TimeInterval {
        let exponent = min(max(consecutiveFailures - 1, 0), 4)
        return min(300 * pow(2, Double(exponent)), 3600)
    }

    nonisolated static func failureKind(for error: any Error) -> FailureKind {
        if let error = error as? CoderPadError {
            switch error {
            case .missingAPIKey: return .other
            case let .http(code, _): return code == 401 || code == 403 ? .unauthorized : .server
            case .decode: return .invalidResponse
            case .network: return .network
            }
        }
        return (error as? URLError) == nil ? .other : .network
    }
}
