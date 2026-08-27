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
import os

/// One CoderPad account, surfaced to the system so it can be picked when configuring
/// the Focus filter in Settings.
struct AccountFocusEntity: AppEntity, Identifiable {
    /// The account's cross-device identity, with a UUID fallback for legacy accounts
    /// that do not yet have enough credential identity to derive one.
    let id: String
    let displayName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Account")
    }

    static let defaultQuery = AccountFocusEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        // Focus settings are system-visible and may appear on shared screenshots.
        // The user-chosen account name identifies the scope without publishing the
        // raw login email outside the app (#1987).
        DisplayRepresentation(title: "\(displayName)")
    }

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    @MainActor
    init(account: Account) {
        self.init(id: AccountFocusIdentity.identifier(for: account), displayName: account.name)
    }
}

enum AccountFocusIdentity {
    static func identifier(for account: Account) -> String {
        account.syncID.isEmpty ? account.id.uuidString : account.syncID
    }

    static func resolve(_ identifier: String, accounts: [Account]) -> Account? {
        if let stable = accounts.first(where: { !$0.syncID.isEmpty && $0.syncID == identifier }) {
            return stable
        }
        guard let uuid = UUID(uuidString: identifier) else { return nil }

        return accounts.first { $0.id == uuid }
    }

    /// Resolves a framework request in stable request order with one indexed pass
    /// over normalized account data. A stable id and its legacy UUID alias may both
    /// be requested, but they still describe one entity (#1426).
    static func resolveAll(_ identifiers: [String], accounts: [Account]) -> [Account] {
        let accounts = unique(accounts)
        var lookup: [String: Account] = [:]
        for account in accounts where !account.syncID.isEmpty {
            if lookup[account.syncID] == nil {
                lookup[account.syncID] = account
            }
        }
        for account in accounts where lookup[account.id.uuidString] == nil {
            lookup[account.id.uuidString] = account
        }

        var seenIdentifiers: Set<String> = []
        var seenAccounts: Set<UUID> = []
        return identifiers.compactMap { identifier in
            guard seenIdentifiers.insert(identifier).inserted,
                  let account = lookup[identifier],
                  seenAccounts.insert(account.id).inserted else { return nil }

            return account
        }
    }

    static func unique(_ accounts: [Account]) -> [Account] {
        var seenLocalIDs: Set<UUID> = []
        var seenEntityIDs: Set<String> = []
        return accounts.filter { account in
            seenLocalIDs.insert(account.id).inserted
                && seenEntityIDs.insert(identifier(for: account)).inserted
        }
    }
}

/// Supplies the configured accounts to the Focus-filter picker. The account store is
/// main-actor bound, so each lookup hops to the main actor before reading it. Only
/// usable accounts (a key to fetch with, or the demo) are offered: scoping a Focus
/// to an account that can't load anything would strand the whole app in a broken
/// scope for the Focus's duration (#1659).
struct AccountFocusEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountFocusEntity] {
        await MainActor.run {
            // Emit in the framework's requested identifier order, not the store's
            // account order, so Focus configuration resolution lines up (#1660).
            let usable = usableAccounts()
            return AccountFocusIdentity.resolveAll(identifiers, accounts: usable).map(AccountFocusEntity.init(account:))
        }
    }

    func suggestedEntities() async throws -> [AccountFocusEntity] {
        await MainActor.run {
            AccountFocusIdentity.unique(usableAccounts()).map(AccountFocusEntity.init(account:))
        }
    }

    @MainActor
    private func usableAccounts() -> [Account] {
        AccountsStore.shared.accounts.filter { account in
            (account.isMock || !account.apiKey.isEmpty) && !account.hasMalformedBaseURLOverride
        }
    }
}

/// What a Focus filter `perform()` call should do, decided from the configured account
/// and whether a pre-Focus snapshot exists. Pure so the transitions are unit-testable;
/// the key distinction is `staleScope` (#796): a configured account that no longer
/// resolves is stale configuration, not a Focus-off transition, so it must neither scope
/// nor restore-and-clear the snapshot.
nonisolated enum FocusFilterAction: Equatable {
    case scope(UUID)
    case staleScope
    case restore
    case noChange

    @MainActor
    static func decide(configuredID: String?, accounts: [Account], hasSnapshot: Bool) -> Self {
        guard let configuredID else { return hasSnapshot ? .restore : .noChange }
        guard let account = AccountFocusIdentity.resolve(configuredID, accounts: accounts) else {
            return .staleScope
        }

        return .scope(account.id)
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

/// The UserDefaults values form one selection snapshot. A process-session marker
/// prevents an uncleanly terminated app from restoring an unrelated old Focus state.
nonisolated enum FocusFilterSnapshot: Equatable {
    case absent
    case incomplete
    case complete(showAll: Bool, account: FocusFilterRestoredAccount)

    static func resolve(savedShowAll: Bool?, savedCurrentID: String?,
                        accounts: [Account], savedSessionID: String? = nil,
                        currentSessionID: String? = nil) -> Self {
        if savedShowAll == nil, savedCurrentID == nil, savedSessionID == nil {
            return .absent
        }
        guard let savedShowAll, let savedCurrentID,
              savedSessionID == currentSessionID else { return .incomplete }

        let account = FocusFilterRestoredAccount.resolve(savedID: savedCurrentID, accounts: accounts)
        guard account != .missingSnapshot else { return .incomplete }

        return .complete(showAll: savedShowAll, account: account)
    }
}

nonisolated enum FocusFilterRestorePolicy {
    /// Restoring is safe only while the selection still matches what Focus imposed.
    /// Any difference is a user choice made during Focus and must survive deactivation.
    static func shouldRestore(showAll: Bool, currentAccountID: UUID?, imposedAccountID: UUID?) -> Bool {
        !showAll && currentAccountID == imposedAccountID
    }
}

/// A process-session-owned stack of active Focus scopes. Every activation gets an
/// ownership token, so nested/overlapping scopes retain the original base selection
/// until the final owner leaves (#1427, #1429). Same-account activations each keep
/// their own entry so two Focus modes targeting one account do not collapse (#4641).
nonisolated struct FocusScopeStack: Codable, Equatable {
    struct Scope: Codable, Equatable {
        let token: UUID
        let accountID: UUID
    }

    let sessionID: String
    let baseShowAll: Bool
    let baseAccountID: String
    private(set) var scopes: [Scope]

    init(sessionID: String, baseShowAll: Bool, baseAccountID: String, scopes: [Scope] = []) {
        self.sessionID = sessionID
        self.baseShowAll = baseShowAll
        self.baseAccountID = baseAccountID
        self.scopes = scopes
    }

    mutating func push(_ accountID: UUID, token: UUID = UUID()) {
        scopes.append(Scope(token: token, accountID: accountID))
    }

    mutating func pop() -> Scope? {
        scopes.popLast()
    }

    /// Collapses overlapping owners down to a single remaining Focus account after
    /// another mode ends out of order (#4642).
    mutating func replaceScopes(withAccount accountID: UUID, token: UUID = UUID()) {
        scopes = [Scope(token: token, accountID: accountID)]
    }

    var imposedAccountID: UUID? {
        scopes.last?.accountID
    }

    var isEmpty: Bool {
        scopes.isEmpty
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

    private static let stackKey = "focusFilter.scopeStack.v2"
    private static let processSessionID = UUID().uuidString

    func perform() async throws -> some IntentResult {
        let action = await applyFocusFilter()
        if action == .staleScope {
            throw $account.needsValueError(
                "That account is no longer set up in PadBuddy. Choose another account in Focus settings."
            )
        }
        return .result()
    }

    /// After relaunch, adopt any previous-process stack and unwind it when Focus is
    /// no longer active so the imposed account is not stranded (#4643).
    @MainActor
    static func reconcileAtLaunch() {
        Task {
            let current = try? await Self.current
            let remainingID: UUID? = {
                guard let configuredID = current?.account?.id else { return nil }

                return AccountFocusIdentity.resolve(
                    configuredID, accounts: AccountsStore.shared.accounts
                )?.id
            }()
            await MainActor.run {
                applyLaunchReconciliation(remainingActiveAccount: remainingID)
            }
        }
    }

    @MainActor
    private func applyFocusFilter() async -> FocusFilterAction {
        if let configuredID = account?.id {
            return activate(configuredID: configuredID)
        }

        // A nil parameter is ambiguous when multiple Focus modes share this filter:
        // another mode may still be active. Ask the system which account (if any) remains
        // before assuming LIFO ownership (#4642).
        let remaining = await remainingActiveAccountID()
        return deactivate(remainingActiveAccount: remaining)
    }

    @MainActor
    private static func applyLaunchReconciliation(remainingActiveAccount: UUID?) {
        let defaults = UserDefaults.standard
        guard var stack = loadStack(defaults) else { return }

        switch FocusDeactivationDecision.decide(
            remainingActiveAccount: remainingActiveAccount,
            hasStack: true
        ) {
        case let .keepScoping(accountID):
            stack.replaceScopes(withAccount: accountID)
            let store = AccountsStore.shared
            store.showAllAccounts = false
            store.currentAccountID = accountID
            save(stack, defaults)

        case .restoreBase:
            let removedAccount = stack.imposedAccountID
            let store = AccountsStore.shared
            if let removedAccount {
                restoreBase(
                    stack,
                    removed: FocusScopeStack.Scope(token: UUID(), accountID: removedAccount),
                    store: store
                )
            }
            defaults.removeObject(forKey: stackKey)

        case .noChange:
            break
        }
    }

    @MainActor
    private func activate(configuredID: String) -> FocusFilterAction {
        let store = AccountsStore.shared
        let defaults = UserDefaults.standard
        guard let selected = AccountFocusIdentity.resolve(configuredID, accounts: store.accounts) else {
            return .staleScope
        }

        var stack = Self.loadStack(defaults) ?? FocusScopeStack(
            sessionID: Self.processSessionID,
            baseShowAll: store.showAllAccounts,
            baseAccountID: store.currentAccountID?.uuidString ?? FocusFilterRestoredAccount.noAccountMarker
        )
        stack.push(selected.id)
        store.showAllAccounts = false
        store.currentAccountID = selected.id
        Self.save(stack, defaults)
        return .scope(selected.id)
    }

    @MainActor
    private func deactivate(remainingActiveAccount: UUID?) -> FocusFilterAction {
        let store = AccountsStore.shared
        let defaults = UserDefaults.standard
        let stack = Self.loadStack(defaults)

        switch FocusDeactivationDecision.decide(
            remainingActiveAccount: remainingActiveAccount,
            hasStack: stack != nil
        ) {
        case let .keepScoping(accountID):
            var stack = stack ?? FocusScopeStack(
                sessionID: Self.processSessionID,
                baseShowAll: store.showAllAccounts,
                baseAccountID: store.currentAccountID?.uuidString ?? FocusFilterRestoredAccount.noAccountMarker
            )
            stack.replaceScopes(withAccount: accountID)
            store.showAllAccounts = false
            store.currentAccountID = accountID
            Self.save(stack, defaults)
            return .scope(accountID)

        case .restoreBase:
            guard let stack else { return .noChange }

            let removedAccount = stack.imposedAccountID ?? UUID(uuidString: stack.baseAccountID)
            if let removedAccount {
                Self.restoreBase(
                    stack,
                    removed: FocusScopeStack.Scope(token: UUID(), accountID: removedAccount),
                    store: store
                )
            }
            defaults.removeObject(forKey: Self.stackKey)
            return .restore

        case .noChange:
            return .noChange
        }
    }

    @MainActor
    private func remainingActiveAccountID() async -> UUID? {
        guard let current = try? await Self.current,
              let configuredID = current.account?.id else { return nil }

        return AccountFocusIdentity.resolve(configuredID, accounts: AccountsStore.shared.accounts)?.id
    }

    @MainActor
    private static func restoreBase(_ stack: FocusScopeStack, removed: FocusScopeStack.Scope,
                                    store: AccountsStore) {
        guard FocusFilterRestorePolicy.shouldRestore(
            showAll: store.showAllAccounts,
            currentAccountID: store.currentAccountID,
            imposedAccountID: removed.accountID
        ) else { return }

        store.currentAccountID = UUID(uuidString: stack.baseAccountID)
        store.showAllAccounts = stack.baseShowAll
    }

    private static func loadStack(_ defaults: UserDefaults) -> FocusScopeStack? {
        guard let data = defaults.data(forKey: stackKey) else {
            defaults.removeObject(forKey: stackKey)
            return nil
        }

        switch FocusScopeStackRestoration.decode(data, expectedSessionID: processSessionID) {
        case let .current(stack):
            return stack

        case let .stale(stack):
            // Keep the pre-Focus base across relaunch so later deactivation can restore
            // it instead of stranding the imposed account (#4643).
            let adopted = FocusScopeStackRestoration.adopt(stack, sessionID: processSessionID)
            save(adopted, defaults)
            return adopted

        case let .failed(message):
            defaults.removeObject(forKey: stackKey)
            persistenceLogger.error("\(message, privacy: .public)")
            return nil
        }
    }

    private static func save(_ stack: FocusScopeStack?, _ defaults: UserDefaults) {
        guard let stack, let data = try? JSONEncoder().encode(stack) else { return }

        defaults.set(data, forKey: stackKey)
    }
}
