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
        if let org = result.org {
            orgByAccount[result.id] = org
            if let client {
                orgCache.set(result.id, organization: org, via: client)
            }
            accountErrors[result.id] = nil
        } else if let errorText = result.errorText {
            accountErrors[result.id] = errorText
        }
        // Stats are window-scoped; org and quota are not (#384/#798).
        if requestedToken == statsWindowToken,
           Self.isCurrentStatsRequest(requestedStatsGeneration, current: statsReloadGeneration) {
            if let stats = result.stats {
                statsByAccount[result.id] = stats
                statsFailures.remove(result.id)
            } else {
                statsByAccount[result.id] = nil
                statsFailures.insert(result.id)
            }
        }
        if let requestedQuotaGeneration,
           requestedQuotaGeneration == quotaReloadGenerations[result.id] {
            quotaFailures = Self.updatingFailures(
                quotaFailures, id: result.id, failed: result.quotaFailed
            )
            if !result.quotaFailed {
                if let quota = result.quota, let client {
                    quotaCache.set(result.id, quota: quota, via: client)
                }
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
