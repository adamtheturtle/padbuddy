//
//  AppCreationAvailability.swift
//  coderpad
//
//  Whether the New Pad / New Question commands can actually complete, shared by the
//  macOS menu bar and the iPad key commands so the two never disagree.
//

import Foundation

enum AppCreationAvailability {
    /// Whether an account has credentials that could actually authenticate a request.
    /// A key of only whitespace passed `!isEmpty` while request construction treated it
    /// as absent, so a shortcut reported success and opened a flow that could not
    /// submit (#4568).
    static func hasUsableCredentials(_ account: Account) -> Bool {
        account.isMock || !account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canCreate(account: Account, isOffline: Bool) -> Bool {
        !isOffline && hasUsableCredentials(account)
    }

    /// Explicit account scopes never fall back to another organization. In the
    /// merged view, an accountless command may use another available account.
    static func creationAccount(
        accounts: [Account], currentAccountID: UUID?, isMergedView: Bool,
        requestedAccountID: UUID?, isOffline: Bool
    ) -> Account? {
        guard !isOffline else { return nil }

        if let requestedAccountID {
            return accounts.first { $0.id == requestedAccountID && hasUsableCredentials($0) }
        }
        if let current = accounts.first(where: { $0.id == currentAccountID && hasUsableCredentials($0) }) {
            return current
        }
        return isMergedView ? accounts.first(where: hasUsableCredentials) : nil
    }

    /// Creation needs an account with credentials to create under and a network to
    /// reach it over. The macOS commands used to check only the network, so with no
    /// account configured — or one whose key had been cleared — they still opened a
    /// flow that could never submit (#2323, #2366).
    @MainActor
    static func canCreate(accounts: AccountsStore, network: NetworkMonitor) -> Bool {
        accounts.accounts.contains { canCreate(account: $0, isOffline: network.isOffline) }
    }
}
