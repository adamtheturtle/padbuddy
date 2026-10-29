import Foundation

extension PadBuddyApp {
    static func validatedAccountID(fromDeepLink url: URL, availableAccounts: [Account]) throws -> UUID? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.filter { $0.name == "account" } ?? []
        guard !items.isEmpty else { return nil }
        guard items.count == 1, let raw = items.first?.value,
              raw.utf8.prefix(65).count <= 64,
              let normalized = WidgetSharedStore.validatedAccount(raw), let normalized,
              let owner = WidgetAccountIdentity.localID(for: normalized, accounts: availableAccounts)
        else { throw DeepLinkAccountError.invalidAccount }

        return owner
    }
}
