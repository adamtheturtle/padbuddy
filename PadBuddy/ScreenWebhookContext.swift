//
//  ScreenWebhookContext.swift
//  coderpad
//

import Foundation

struct ScreenWebhookContext: Hashable {
    let accountID: UUID
    let clientIdentity: ClientTaskIdentity

    func matches(accountID: UUID, clientIdentity: ClientTaskIdentity) -> Bool {
        self.accountID == accountID && self.clientIdentity == clientIdentity
    }
}
