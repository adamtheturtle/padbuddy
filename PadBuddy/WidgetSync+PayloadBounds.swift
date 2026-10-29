import Foundation

extension WidgetSync {
    static let maximumIndexedAccounts = 256

    static func accountIndex(_ accounts: [Account]) -> [WidgetAccount] {
        accounts.prefix(maximumIndexedAccounts).map { account in
            let identifier = WidgetAccountIdentity.identifier(for: account)
            let name = ExternalText.singleLine(account.name, limit: 128)
            return WidgetAccount(
                id: identifier, name: name.isEmpty ? String(identifier.prefix(8)) : name,
                legacyID: account.id.uuidString
            )
        }
    }
}
