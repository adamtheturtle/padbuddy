//
//  AppNavigation+NewPad.swift
//  coderpad
//
//  New Pad routing, split from AppNavigation.swift to keep that file under the
//  file-length limit.
//

import Foundation

extension AppNavigation {
    /// Switches to the requested account (if any) and opens the Pads create sheet —
    /// the shared destination of the `com.adamdangoor.padbuddy://new-pad` deep link, the macOS
    /// widget/Control Center/Dock New Pad paths, and the iPad deep-link handler. An
    /// account is honoured only when it still exists; the seeded question id is only
    /// unique within its owning org, so the account switch must happen first. Lives
    /// here (pure navigation, no AppKit) so it is callable on every platform.
    @MainActor
    func routeNewPad(account: String?, seedQuestionID: Int?, createError: String? = nil) {
        let accounts = AccountsStore.shared.accounts
        let localAccount = account.flatMap { WidgetAccountIdentity.localID(for: $0, accounts: accounts) }
        var route = Self.resolveNewPadRoute(
            account: localAccount?.uuidString ?? account,
            seedQuestionID: seedQuestionID,
            availableAccountIDs: accounts.map(\.id)
        )
        // The account resolving is not enough: a widget button configured before a
        // question was unfavourited — or against an account that has since been
        // re-created — still carries an id the target org may not own, and per-org ids
        // collide across orgs, so seeding blindly can create the pad from an entirely
        // different question (#2365). The widget only ever offers favourites, so a seed
        // the account no longer favourites is stale; drop it and open the flow unseeded
        // rather than creating from the wrong question.
        if let accountID = route.accountID, let seed = route.seedQuestionID,
           !FavoriteQuestionsStore.shared.isFavorite(seed, account: accountID) {
            route.seedQuestionID = nil
        }
        if let uuid = route.accountID {
            AccountsStore.shared.showAllAccounts = false
            AccountsStore.shared.currentAccountID = uuid
        }
        showPads(PadsRequest(startCreating: true, seedQuestionID: route.seedQuestionID, createError: createError))
    }

    static func resolveNewPadRoute(
        account: String?,
        seedQuestionID: Int?,
        availableAccountIDs: some Collection<UUID>
    ) -> (accountID: UUID?, seedQuestionID: Int?) {
        // Zero/negative seeds are malformed deep-link data, never real question
        // ids (#1828).
        let validSeed = seedQuestionID.flatMap { $0 > 0 ? $0 : nil }
        guard let account, !account.isEmpty else {
            // Per-org question ids are meaningless without their owning account:
            // a seed arriving accountless (a stale widget or deep link) must not
            // apply another organization's id to the current account (#1829).
            return (nil, nil)
        }
        guard let uuid = UUID(uuidString: account),
              availableAccountIDs.contains(uuid) else {
            return (nil, nil)
        }

        return (uuid, validSeed)
    }
}
