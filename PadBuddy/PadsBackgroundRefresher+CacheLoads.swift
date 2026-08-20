//
//  PadsBackgroundRefresher+CacheLoads.swift
//  coderpad
//

import Foundation

extension PadsBackgroundRefresher {
    /// Put accounts with an in-progress interview into the first bounded fetch
    /// wave. The stable partition preserves account order within each priority.
    static func prioritize(_ jobs: [FetchJob]) -> [FetchJob] {
        let grouped = Dictionary(grouping: jobs) { job in
            PadsCacheStore.shared.get(job.accountID).contains { $0.status == .active }
        }
        return (grouped[true] ?? []) + (grouped[false] ?? [])
    }

    static func beginCacheLoads(for jobs: [FetchJob]) -> [UUID: Int] {
        // Coalesce duplicate account jobs before `beginLoad`: calling it twice for the
        // same UUID would both waste a load generation and trap `uniqueKeysWithValues`
        // (#4616). First job wins — duplicates name the same backend.
        var loads: [UUID: Int] = [:]
        for job in jobs {
            guard loads[job.accountID] == nil else { continue }
            guard let account = AccountsStore.shared.accounts.first(where: { $0.id == job.accountID }),
                  let token = PadsCacheStore.shared.beginLoad(account.id, via: account.makeClient())
            else { continue }

            loads[account.id] = token
        }
        return loads
    }
}
