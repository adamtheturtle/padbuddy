//
//  MergedOrganizationView+ReloadIdentity.swift
//  coderpad
//

import Foundation
import os

nonisolated enum MergedOrganizationRequestOutcome<Value> {
    case value(Value)
    case failed(String)
}

nonisolated enum MergedOrganizationRequest {
    static func evaluate<Value>(
        context: String,
        load: () async throws -> Value
    ) async throws -> MergedOrganizationRequestOutcome<Value> {
        do {
            return try await .value(load())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failed("\(context): \(error.localizedDescription)")
        }
    }
}

enum MergedOrganizationReloadResult {
    case organization(id: UUID, value: Organization?, errorText: String?)
    case stats(id: UUID, value: OrganizationStats?)
    case quota(id: UUID, value: Quota?, failed: Bool)

    var id: UUID {
        switch self {
        case let .organization(id, _, _), let .stats(id, _), let .quota(id, _, _): id
        }
    }
}

struct MergedOrganizationReloadTarget {
    let id: UUID
    let client: CoderPadClient
    let clientIdentity: ClientTaskIdentity

    init(id: UUID, client: CoderPadClient) {
        self.id = id
        self.client = client
        clientIdentity = client.taskIdentity
    }
}

struct MergedOrganizationStatsResult {
    let id: UUID
    let clientIdentity: ClientTaskIdentity
    let stats: OrganizationStats?
}

struct MergedOrganizationReloadContext {
    let generation: Int
    let statsGeneration: Int
    let window: (start: Date, end: Date)
    let token: StatsWindowToken
    let quotaGenerations: [UUID: Int]
}

extension MergedOrganizationView {
    private static let reloadLogger = Logger(
        subsystem: "com.coderpad.app",
        category: "merged-organization-reload"
    )

    static func secondaryRefreshFailureMessage(statsFailed: Bool, quotaFailed: Bool) -> String? {
        switch (statsFailed, quotaFailed) {
        case (true, true): String(localized: "The pad stats and quota requests failed.")
        case (true, false): String(localized: "The pad stats request failed.")
        case (false, true): String(localized: "The quota request failed.")
        case (false, false): nil
        }
    }

    static func fetchOrganization(
        _ target: MergedOrganizationReloadTarget
    ) async throws -> MergedOrganizationReloadResult {
        do {
            return try await .organization(
                id: target.id, value: target.client.organization(), errorText: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .organization(id: target.id, value: nil, errorText: error.localizedDescription)
        }
    }

    static func fetchStats(
        _ target: MergedOrganizationReloadTarget,
        window: (start: Date, end: Date)
    ) async throws -> MergedOrganizationReloadResult {
        switch try await MergedOrganizationRequest.evaluate(
            context: "Could not refresh pad stats",
            load: { try await target.client.organizationStats(start: window.start, end: window.end) }
        ) {
        case let .value(value):
            return .stats(id: target.id, value: value)
        case let .failed(message):
            reloadLogger.error("\(message, privacy: .public); account: \(target.id, privacy: .public)")
            return .stats(id: target.id, value: nil)
        }
    }

    static func fetchQuota(
        _ target: MergedOrganizationReloadTarget
    ) async throws -> MergedOrganizationReloadResult {
        do {
            return try await .quota(id: target.id, value: target.client.quota(), failed: false)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .quota(id: target.id, value: nil, failed: true)
        }
    }

    static func isCurrentReload(_ generation: Int, current: Int) -> Bool {
        generation == current
    }

    static func isCurrentStatsRequest(_ generation: Int, current: Int) -> Bool {
        generation == current
    }

    static func isCurrentTarget(_ requested: ClientTaskIdentity, current: ClientTaskIdentity?) -> Bool {
        requested == current
    }

    static func retainingEntries<Value>(_ entries: [UUID: Value], for liveIDs: Set<UUID>) -> [UUID: Value] {
        entries.filter { liveIDs.contains($0.key) }
    }

    static func retainingFailures(_ failures: Set<UUID>, for eligibleIDs: Set<UUID>) -> Set<UUID> {
        failures.intersection(eligibleIDs)
    }

    static func updatingFailures(_ failures: Set<UUID>, id: UUID, failed: Bool) -> Set<UUID> {
        var updated = failures
        if failed {
            updated.insert(id)
        } else {
            updated.remove(id)
        }
        return updated
    }

    /// Aggregate tiles are authoritative only when every eligible account supplied
    /// a current value and none of those accounts reported a failure.
    static func hasCompleteCoverage(
        eligibleIDs: Set<UUID>, loadedIDs: Set<UUID>, failedIDs: Set<UUID>
    ) -> Bool {
        eligibleIDs.isSubset(of: loadedIDs) && eligibleIDs.isDisjoint(with: failedIDs)
    }
}
