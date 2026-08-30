//
//  MergedOrganizationView+ReloadApplication.swift
//  coderpad
//

import Foundation

extension MergedOrganizationView {
    func reloadQuota(for account: Account) async {
        guard !account.apiKey.isEmpty, !quotaLoadingIDs.contains(account.id) else { return }

        let client = account.makeClient()
        let requestedIdentity = client.taskIdentity
        quotaReloadGenerations[account.id, default: 0] &+= 1
        let generation = quotaReloadGenerations[account.id, default: 0]
        quotaLoadingIDs.insert(account.id)
        defer {
            if quotaReloadGenerations[account.id] == generation {
                quotaLoadingIDs.remove(account.id)
            }
        }
        do {
            let quota = try await client.quota()
            guard !Task.isCancelled, quotaReloadGenerations[account.id] == generation,
                  currentClient(for: MergedOrganizationReloadTarget(id: account.id, client: client)) != nil
            else { return }

            quotaCache.set(account.id, quota: quota, via: client)
            quotaFailures.remove(account.id)
        } catch {
            let currentIdentity = accounts.mergeableAccounts
                .first(where: { $0.id == account.id })?.makeClient().taskIdentity
            guard !Task.isCancelled, quotaReloadGenerations[account.id] == generation,
                  requestedIdentity == currentIdentity else { return }

            quotaFailures.insert(account.id)
        }
    }

    func applyReloadResult(_ result: MergedOrganizationReloadResult,
                           requestedToken: StatsWindowToken, requestedStatsGeneration: Int,
                           client: CoderPadClient?,
                           requestedQuotaGeneration: Int?) {
        switch result {
        case let .organization(id, org, errorText):
            if let org {
                orgByAccount[id] = org
                if let client {
                    orgCache.set(id, organization: org, via: client)
                }
                accountErrors[id] = nil
            } else if let errorText {
                accountErrors[id] = errorText
            }

        case let .stats(id, stats):
            guard requestedToken == statsWindowToken,
                  Self.isCurrentStatsRequest(
                      requestedStatsGeneration, current: statsReloadGeneration
                  ) else { return }

            if let stats {
                statsByAccount[id] = stats
                statsFailures.remove(id)
            } else {
                statsByAccount[id] = nil
                statsFailures.insert(id)
            }

        case let .quota(id, quota, failed):
            guard let requestedQuotaGeneration,
                  requestedQuotaGeneration == quotaReloadGenerations[id] else { return }

            quotaFailures = Self.updatingFailures(quotaFailures, id: id, failed: failed)
            if !failed, let quota, let client {
                quotaCache.set(id, quota: quota, via: client)
            }
        }
    }

    func currentClient(for target: MergedOrganizationReloadTarget) -> CoderPadClient? {
        guard let account = accounts.mergeableAccounts.first(where: { $0.id == target.id }),
              !account.apiKey.isEmpty else { return nil }

        let client = account.makeClient()
        return Self.isCurrentTarget(target.clientIdentity, current: client.taskIdentity) ? client : nil
    }

    func discardStaleResult(for id: UUID) {
        orgByAccount[id] = nil
        statsByAccount[id] = nil
        accountErrors[id] = nil
        statsFailures.remove(id)
        quotaFailures.remove(id)
    }
}
