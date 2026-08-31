//
//  FocusFilter+Intent.swift
//  coderpad
//
//
//  The SetFocusFilterIntent itself; the entity, identity and scope-stack model it

import AppIntents
import Foundation
import os

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

    /// Reset persisted Focus restoration without stranding the currently imposed
    /// account. If the user changed selection after Focus activated, that choice is
    /// preserved and only the obsolete stack is removed (#5152).
    @MainActor
    static func resetRestorationState() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: stackKey) }
        guard let stack = loadStack(defaults) else { return }

        let store = AccountsStore.shared
        guard let selection = FocusScopeStackReset.selection(
            for: stack,
            currentShowAll: store.showAllAccounts,
            currentAccountID: store.currentAccountID
        ) else { return }

        store.currentAccountID = selection.accountID
        store.showAllAccounts = selection.showAll
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
        // The same usability predicate the picker offers options through: an account that
        // has since lost its key or acquired a malformed base URL would otherwise be
        // scoped to, and every section would load nothing until the Focus ends (#4732).
        // `.staleScope` is what `perform()` already surfaces as a needs-value error.
        guard let selected = AccountFocusIdentity.resolve(configuredID, accounts: store.accounts),
              AccountFocusIdentity.isUsableForFocus(selected) else {
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
