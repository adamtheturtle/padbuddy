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
        Dictionary(uniqueKeysWithValues: jobs.compactMap { job in
            AccountsStore.shared.accounts.first(where: { $0.id == job.accountID }).flatMap { account in
                PadsCacheStore.shared.beginLoad(account.id, via: account.makeClient()).map { (account.id, $0) }
            }
        })
    }
}
