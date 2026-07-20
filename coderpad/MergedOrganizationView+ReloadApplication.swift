//
//  MergedOrganizationView+ReloadApplication.swift
//  coderpad
//

import Foundation

extension MergedOrganizationView {
    func applyReloadResult(_ result: MergedOrganizationReloadResult,
                           requestedToken: StatsWindowToken, client: CoderPadClient?) {
        if let org = result.org {
            orgByAccount[result.id] = org
            if let client { orgCache.set(result.id, organization: org, via: client) }
            accountErrors[result.id] = nil
        } else if let errorText = result.errorText {
            accountErrors[result.id] = errorText
        }
        // Stats are window-scoped; org and quota are not (#384/#798).
        if requestedToken == statsWindowToken {
            if let stats = result.stats {
                statsByAccount[result.id] = stats
                statsFailures.remove(result.id)
            } else {
                statsByAccount[result.id] = nil
                statsFailures.insert(result.id)
            }
        }
        if let quota = result.quota, let client { quotaCache.set(result.id, quota: quota, via: client) }
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
    }
}
