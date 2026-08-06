//
//  ScreenTestsView+ActionContext.swift
//  coderpad
//

import Foundation

nonisolated struct ScreenTestsActionContext: Hashable {
    let clientIdentity: ClientTaskIdentity
    let campaignID: Int
    let accountID: UUID?

    func isCurrent(
        clientIdentity currentClientIdentity: ClientTaskIdentity,
        campaignID currentCampaignID: Int?,
        accountID currentAccountID: UUID?
    ) -> Bool {
        clientIdentity == currentClientIdentity
            && campaignID == currentCampaignID
            && accountID == currentAccountID
    }
}
