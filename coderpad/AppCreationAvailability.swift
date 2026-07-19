//
//  AppCreationAvailability.swift
//  coderpad
//
//  Whether the New Pad / New Question commands can actually complete, shared by the
//  macOS menu bar and the iPad key commands so the two never disagree.
//

import Foundation

enum AppCreationAvailability {
    /// Creation needs an account with credentials to create under and a network to
    /// reach it over. The macOS commands used to check only the network, so with no
    /// account configured — or one whose key had been cleared — they still opened a
    /// flow that could never submit (#2323, #2366).
    @MainActor
    static func canCreate(accounts: AccountsStore, network: NetworkMonitor) -> Bool {
        guard !network.isOffline else { return false }

        return accounts.accounts.contains { $0.isMock || !$0.apiKey.isEmpty }
    }
}
