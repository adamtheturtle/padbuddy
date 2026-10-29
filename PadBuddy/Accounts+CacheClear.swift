//
//  Accounts+CacheClear.swift
//  coderpad
//

import Foundation

extension AccountsStore {
    /// Clears disposable data for one account without touching its credentials,
    /// favorites, filters, or other user-authored preferences.
    func clearCachedData(for accountID: UUID) async {
        guard let account = accounts.first(where: { $0.id == accountID }) else { return }

        // Fence pre-clear list requests before invalidating their published
        // snapshots. Success is announced only after the coalescer is cleared.
        await APIReadCoordinator.shared.remove(accountID: accountID)
        PadsCacheStore.shared.invalidateSnapshot(accountID)
        QuestionsCacheStore.shared.invalidateSnapshot(accountID)
        OrganizationCacheStore.shared.remove(accountID)
        QuotaCacheStore.shared.remove(accountID)
        DirectoryCache.remove(account: accountID)
        CacheLoadDiagnostics.clear(account: accountID)

        let client = account.makeClient()
        OrganizationCacheStore.shared.remove(baseURL: client.baseURL, apiKey: client.apiKey)
        PadDetailCacheStore.shared.remove(baseURL: client.baseURL, apiKey: client.apiKey)
        PadDetailCacheStore.shared.reinstate(baseURL: client.baseURL, apiKey: client.apiKey)
    }
}
