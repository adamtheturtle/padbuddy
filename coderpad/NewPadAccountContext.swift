//
//  NewPadAccountContext.swift
//  coderpad
//

import Foundation

struct AccountClientContext {
    let accountID: UUID?
    let clientIdentity: ClientTaskIdentity

    init(client: CoderPadClient, targetAccountID: UUID?) {
        accountID = targetAccountID ?? AccountsStore.shared.account(matching: client)?.id
        clientIdentity = client.taskIdentity
    }

    func resolve(in accounts: [Account]) -> Account? {
        guard let accountID else { return nil }

        return accounts.first { account in
            account.id == accountID && account.makeClient().taskIdentity == clientIdentity
        }
    }
}

enum AccountClientContextError: LocalizedError {
    case accountChanged

    var errorDescription: String? {
        String(localized: "That account changed while creating the pad. Try again.")
    }
}
