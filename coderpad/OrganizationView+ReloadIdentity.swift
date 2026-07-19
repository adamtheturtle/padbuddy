//
//  OrganizationView+ReloadIdentity.swift
//  coderpad
//

nonisolated enum OrganizationReloadIdentity {
    static func isCurrent(
        _ generation: Int,
        currentGeneration: Int,
        requestedOwner: OrganizationStatsOwner,
        currentOwner: OrganizationStatsOwner
    ) -> Bool {
        generation == currentGeneration && requestedOwner == currentOwner
    }
}
