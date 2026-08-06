//
//  Accounts+CacheClear.swift
//  coderpad
//

import Foundation

extension AccountsStore {
    /// Clears disposable data for one account without touching its credentials,
    /// favorites, filters, or other user-authored preferences.
    func clearCachedData(for accountID: UUID) {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }

        PadsCacheStore.shared.invalidateSnapshot(accountID)
        QuestionsCacheStore.shared.invalidateSnapshot(accountID)
        OrganizationCacheStore.shared.remove(accountID)
        QuotaCacheStore.shared.remove(accountID)

        let client = account.makeClient()
        OrganizationCacheStore.shared.remove(baseURL: client.baseURL, apiKey: client.apiKey)
        PadDetailCacheStore.shared.remove(baseURL: client.baseURL, apiKey: client.apiKey)
        PadDetailCacheStore.shared.reinstate(baseURL: client.baseURL, apiKey: client.apiKey)
    }
}
