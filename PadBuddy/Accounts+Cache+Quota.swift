//
//  Accounts+Cache+Quota.swift
//  coderpad
//
//  The per-account quota cache, split from Accounts+Cache.swift for file length.
//

import Foundation

/// Holds the last-loaded quota per account, for the same reason as
/// `OrganizationCacheStore`. Shared by both the Quota and Organization sections,
/// so visiting either one warms the other.
@Observable
final class QuotaCacheStore {
    static let shared = QuotaCacheStore()
    private(set) var byAccount: [UUID: Quota] = [:]
    private init() {}

    func get(_ accountID: UUID) -> Quota? {
        byAccount[accountID]
    }

    /// `client` is the client the quota was fetched through; a stale result from a
    /// removed or re-keyed account's outstanding load is dropped (#754).
    func set(_ accountID: UUID, quota: Quota, via client: CoderPadClient) {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return }

        byAccount[accountID] = quota
    }

    func remove(_ accountID: UUID) {
        byAccount[accountID] = nil
    }
}
