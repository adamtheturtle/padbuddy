//
//  AccountSectionHeader.swift
//  coderpad
//
//  The per-account section header shared by the combined Organization and Quota
//  views, split out of MergedQuotaView.swift for file length.
//

import SwiftUI

/// The identifying header atop each account's section in the combined Organization
/// and Quota views: the account avatar, its name, and the key owner's email.
struct AccountSectionHeader: View {
    let account: Account
    @AppStorage(GeneralSettings.Key.showAccountEmailsInSectionHeaders) private var showEmail = false

    private var identity: AccountSectionHeaderIdentity {
        AccountSectionHeaderIdentity(account: account, showEmail: showEmail)
    }

    var body: some View {
        HStack(spacing: 10) {
            AvatarCircle(account: account, diameter: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(identity.displayName).font(.headline)
                if let email = identity.email {
                    Text(email).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AccountSectionHeaderIdentity: Equatable {
    let displayName: String
    let email: String?

    init(account: Account, showEmail: Bool) {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownerEmail = account.userEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        if !name.isEmpty {
            displayName = name
            email = showEmail && !ownerEmail.isEmpty && ownerEmail != name ? ownerEmail : nil
        } else if showEmail, !ownerEmail.isEmpty {
            displayName = ownerEmail
            email = nil
        } else {
            displayName = String(localized: "Account")
            email = nil
        }
    }
}
