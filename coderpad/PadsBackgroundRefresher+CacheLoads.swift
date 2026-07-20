//
//  PadsBackgroundRefresher+CacheLoads.swift
//  coderpad
//

import Foundation

extension PadsBackgroundRefresher {
    static func beginCacheLoads(for jobs: [FetchJob]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: jobs.compactMap { job in
            AccountsStore.shared.accounts.first(where: { $0.id == job.accountID }).flatMap { account in
                PadsCacheStore.shared.beginLoad(account.id, via: account.makeClient()).map { (account.id, $0) }
            }
        })
    }
}
