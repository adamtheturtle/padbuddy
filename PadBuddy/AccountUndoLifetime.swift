import Foundation

/// Undo snapshots belong to the account lifetime in which they were captured.
/// Removal drops the token entirely; reusing the UUID creates a new lifetime.
enum AccountUndoLifetime {
    private static var tokens: [UUID: UUID] = [:]

    struct Snapshot {
        let captured: [UUID: UUID]

        var isCurrent: Bool {
            captured.allSatisfy { tokens[$0.key] == $0.value }
        }
    }

    static func capture(_ accounts: Set<UUID>) -> Snapshot {
        var captured: [UUID: UUID] = [:]
        for account in accounts {
            let token = tokens[account] ?? UUID()
            tokens[account] = token
            captured[account] = token
        }
        return Snapshot(captured: captured)
    }

    static func invalidate(_ account: UUID) {
        tokens[account] = nil
    }
}
