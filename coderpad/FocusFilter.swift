//
//  FocusFilter.swift
//  coderpad
//
//  A Focus filter (#595) that scopes the whole app to a single CoderPad account
//  while a Focus (e.g. "Work", "Interviewing") is on. CoderPad accounts map 1:1 to
//  orgs, so scoping to an account is scoping to an org.
//
//  The filter drives the same selection the in-app account switcher uses -
//  `showAllAccounts` + `currentAccountID` on the shared `AccountsStore` - rather than
//  introducing a parallel filtering path. Turning the Focus on snapshots the user's
//  pre-Focus selection; turning it off restores exactly that, so the scope is
//  transient and never strands a multi-account user in a single account.
//

import AppIntents
import Foundation

/// One CoderPad account, surfaced to the system so it can be picked when configuring
/// the Focus filter in Settings.
struct AccountFocusEntity: AppEntity, Identifiable {
    /// The account's UUID, as a string (AppEntity ids are stable across launches).
    let id: String
    let displayName: String
    let email: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Account")
    }

    static let defaultQuery = AccountFocusEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayName)", subtitle: "\(email)")
    }

    init(id: String, displayName: String, email: String) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }

    @MainActor
    init(account: Account) {
        self.init(id: account.id.uuidString, displayName: account.name, email: account.userEmail)
    }
}

/// Supplies the configured accounts to the Focus-filter picker. The account store is
/// main-actor bound, so each lookup hops to the main actor before reading it.
struct AccountFocusEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountFocusEntity] {
        await MainActor.run {
            AccountsStore.shared.accounts
                .filter { identifiers.contains($0.id.uuidString) }
                .map(AccountFocusEntity.init(account:))
        }
    }

    func suggestedEntities() async throws -> [AccountFocusEntity] {
        await MainActor.run {
            AccountsStore.shared.accounts.map(AccountFocusEntity.init(account:))
        }
    }
}

/// What a Focus filter `perform()` call should do, decided from the configured account
/// and whether a pre-Focus snapshot exists. Pure so the transitions are unit-testable;
/// the key distinction is `ignoreStaleScope` (#796): a configured account that no longer
/// resolves is stale configuration, not a Focus-off transition, so it must neither scope
/// nor restore-and-clear the snapshot.
nonisolated enum FocusFilterAction: Equatable {
    case scope(UUID)
    case ignoreStaleScope
    case restore
    case noChange

    static func decide(configuredID: String?, accounts: [Account], hasSnapshot: Bool) -> Self {
        guard let configuredID else { return hasSnapshot ? .restore : .noChange }
        guard let uuid = UUID(uuidString: configuredID),
              accounts.contains(where: { $0.id == uuid }) else { return .ignoreStaleScope }

        return .scope(uuid)
    }
}

nonisolated enum FocusFilterRestoredAccount: Equatable {
    case missingSnapshot
    case noAccount
    case account(UUID)

    static let noAccountMarker = ""

    static func resolve(savedID: String?, accounts: [Account]) -> Self {
        guard let savedID else { return .missingSnapshot }
        guard !savedID.isEmpty else { return .noAccount }
        guard let uuid = UUID(uuidString: savedID),
              accounts.contains(where: { $0.id == uuid }) else { return .missingSnapshot }

        return .account(uuid)
    }
}

/// Limits the app to one account while a Focus is active. When the Focus turns off the
/// system calls `perform()` again with `account == nil`, which restores the snapshot.
struct ScopeToAccountFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Scope to Account"
    // Read by the AppIntents framework (Focus settings metadata), not Swift.
    // periphery:ignore
    static let description = IntentDescription(
        "Limit PadBuddy to a single CoderPad account while a Focus is on."
    )

    @Parameter(title: "Account")
    var account: AccountFocusEntity?

    var displayRepresentation: DisplayRepresentation {
        if let account {
            DisplayRepresentation(title: "Scoped to \(account.displayName)")
        } else {
            DisplayRepresentation(title: "All accounts")
        }
    }

    private static let savedShowAllKey = "focusFilter.savedShowAllAccounts"
    private static let savedCurrentKey = "focusFilter.savedCurrentAccountID"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            let store = AccountsStore.shared
            let defaults = UserDefaults.standard

            switch FocusFilterAction.decide(
                configuredID: account?.id,
                accounts: store.accounts,
                hasSnapshot: defaults.object(forKey: Self.savedShowAllKey) != nil
            ) {
            case let .scope(uuid):
                // Entering a Focus-scoped state: snapshot the pre-Focus selection once,
                // so a later Focus switch (account A -> account B with no "off" between)
                // keeps the original snapshot to restore at the end.
                if defaults.object(forKey: Self.savedShowAllKey) == nil {
                    defaults.set(store.showAllAccounts, forKey: Self.savedShowAllKey)
                    defaults.set(
                        store.currentAccountID?.uuidString ?? FocusFilterRestoredAccount.noAccountMarker,
                        forKey: Self.savedCurrentKey
                    )
                }
                store.showAllAccounts = false
                store.currentAccountID = uuid

            case .ignoreStaleScope, .noChange:
                // Stale scope (#796): the configured account was removed, so this is
                // not a Focus-off transition. Leave the selection and any snapshot
                // untouched so the real off transition can still restore it.
                break

            case .restore:
                // Focus turned off: restore whatever was selected before it began.
                let savedShowAll = defaults.bool(forKey: Self.savedShowAllKey)
                switch FocusFilterRestoredAccount.resolve(
                    savedID: defaults.string(forKey: Self.savedCurrentKey),
                    accounts: store.accounts
                ) {
                case let .account(uuid):
                    store.currentAccountID = uuid
                case .noAccount:
                    store.currentAccountID = nil
                case .missingSnapshot:
                    break
                }
                store.showAllAccounts = savedShowAll
                defaults.removeObject(forKey: Self.savedShowAllKey)
                defaults.removeObject(forKey: Self.savedCurrentKey)
            }
        }
        return .result()
    }
}
