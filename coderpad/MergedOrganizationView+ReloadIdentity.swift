//
//  MergedOrganizationView+ReloadIdentity.swift
//  coderpad
//

import Foundation

struct MergedOrganizationReloadResult {
    let id: UUID
    let org: Organization?
    let stats: OrganizationStats?
    let quota: Quota?
    let errorText: String?
}

extension MergedOrganizationView {
    static func isCurrentReload(_ generation: Int, current: Int) -> Bool {
        generation == current
    }

    static func retainingEntries<Value>(_ entries: [UUID: Value], for liveIDs: Set<UUID>) -> [UUID: Value] {
        entries.filter { liveIDs.contains($0.key) }
    }
}
