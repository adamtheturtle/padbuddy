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

struct MergedOrganizationReloadResult {
    let id: UUID
    let org: Organization?
    let stats: OrganizationStats?
    let quota: Quota?
    let quotaFailed: Bool
    let errorText: String?
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

    static func fetch(
        _ target: MergedOrganizationReloadTarget,
        window: (start: Date, end: Date)
    ) async -> MergedOrganizationReloadResult {
        let org: Organization?
        let errorText: String?
        do {
            org = try await target.client.organization()
            errorText = nil
        } catch {
            org = nil
            errorText = error.localizedDescription
        }
        let stats: OrganizationStats?
        do {
            switch try await MergedOrganizationRequest.evaluate(
                context: "Could not refresh pad stats",
                load: { try await target.client.organizationStats(start: window.start, end: window.end) }
            ) {
            case let .value(value):
                stats = value
            case let .failed(message):
                stats = nil
                reloadLogger.error("\(message, privacy: .public); account: \(target.id, privacy: .public)")
            }
        } catch is CancellationError {
            return MergedOrganizationReloadResult(
                id: target.id, org: org, stats: nil, quota: nil,
                quotaFailed: false, errorText: errorText
            )
        } catch {
            assertionFailure("Merged organization request only throws cancellation: \(error)")
            stats = nil
        }
        let quota: Quota?
        let quotaFailed: Bool
        do {
            quota = try await target.client.quota()
            quotaFailed = false
        } catch {
            quota = nil
            quotaFailed = true
        }
        return MergedOrganizationReloadResult(
            id: target.id, org: org, stats: stats, quota: quota,
            quotaFailed: quotaFailed, errorText: errorText
        )
    }

    static func isCurrentReload(_ generation: Int, current: Int) -> Bool {
        generation == current
    }

    static func isCurrentTarget(_ requested: ClientTaskIdentity, current: ClientTaskIdentity?) -> Bool {
        requested == current
    }

    static func retainingEntries<Value>(_ entries: [UUID: Value], for liveIDs: Set<UUID>) -> [UUID: Value] {
        entries.filter { liveIDs.contains($0.key) }
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
