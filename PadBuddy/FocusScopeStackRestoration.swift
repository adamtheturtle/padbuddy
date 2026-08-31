//
//  FocusScopeStackRestoration.swift
//  PadBuddy
//

import Foundation

nonisolated enum FocusScopeStackRestoration {
    case current(FocusScopeStack)
    /// A stack from a previous process. The base selection must survive so a Focus
    /// that stayed active across relaunch can still restore on deactivation (#4643).
    case stale(FocusScopeStack)
    case failed(String)

    static func decode(
        _ data: Data,
        expectedSessionID: String,
        using decode: (Data) throws -> FocusScopeStack = {
            try JSONDecoder().decode(FocusScopeStack.self, from: $0)
        }
    ) -> Self {
        do {
            let stack = try decode(data)
            if stack.sessionID == expectedSessionID {
                return .current(stack)
            }
            return .stale(stack)
        } catch {
            return .failed("Could not restore the Focus account scope stack: \(error.localizedDescription)")
        }
    }

    /// Rebinds a previous-process stack to the live session while preserving the
    /// pre-Focus base selection and any recorded owners.
    static func adopt(_ stack: FocusScopeStack, sessionID: String) -> FocusScopeStack {
        FocusScopeStack(
            sessionID: sessionID,
            baseShowAll: stack.baseShowAll,
            baseAccountID: stack.baseAccountID,
            scopes: stack.scopes
        )
    }
}

/// Pure decision helper for Focus deactivation when the system passes a nil account.
/// `remainingActiveAccount` comes from `SetFocusFilterIntent.current` so out-of-order
/// Focus ends do not LIFO-pop the wrong owner (#4642).
nonisolated enum FocusDeactivationDecision: Equatable {
    case keepScoping(UUID)
    case restoreBase
    case noChange

    static func decide(remainingActiveAccount: UUID?, hasStack: Bool) -> Self {
        if let remainingActiveAccount {
            return .keepScoping(remainingActiveAccount)
        }
        return hasStack ? .restoreBase : .noChange
    }
}

nonisolated struct FocusScopeResetSelection: Equatable {
    let showAll: Bool
    let accountID: UUID?
}

/// Restores the pre-Focus selection only while the live selection still matches what
/// Focus imposed. A later user choice wins, but the obsolete restoration stack may
/// still be discarded by Reset Restored App State (#5152).
nonisolated enum FocusScopeStackReset {
    static func selection(
        for stack: FocusScopeStack,
        currentShowAll: Bool,
        currentAccountID: UUID?
    ) -> FocusScopeResetSelection? {
        guard FocusFilterRestorePolicy.shouldRestore(
            showAll: currentShowAll,
            currentAccountID: currentAccountID,
            imposedAccountID: stack.imposedAccountID
        ) else { return nil }

        return FocusScopeResetSelection(
            showAll: stack.baseShowAll,
            accountID: UUID(uuidString: stack.baseAccountID)
        )
    }
}
