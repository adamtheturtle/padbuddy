//
//  MenuBarCreateContext.swift
//  coderpad
//

import Foundation

struct MenuBarCreateContext: Equatable {
    let accountID: UUID
    let clientIdentity: ClientTaskIdentity

    init(account: Account) {
        accountID = account.id
        clientIdentity = account.makeClient().taskIdentity
    }

    func resolve(in accounts: [Account]) -> Account? {
        accounts.first { account in
            account.id == accountID && account.makeClient().taskIdentity == clientIdentity
        }
    }
}

enum MenuBarCreateError: LocalizedError {
    case accountChanged

    var errorDescription: String? {
        String(localized: "That account changed while creating the pad. Try again.")
    }
}
