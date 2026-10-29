import AppGroupMailbox
import Foundation
import OSLog

nonisolated extension WidgetSharedStore {
    /// Claim finalization is idempotent; transient failures get a bounded retry.
    static func completeHandoffCleanup(context: String, operation: () throws -> Void) -> Bool {
        for attempt in 1 ... 3 {
            do {
                try operation()
                return true
            } catch AppGroupMailbox<WidgetPendingRequest>.MailboxError.claimNoLongerExists {
                return true
            } catch {
                logger.error("""
                Widget cleanup \(context, privacy: .public), attempt \(attempt):
                \(error.localizedDescription, privacy: .private)
                """)
            }
        }
        return false
    }
}
