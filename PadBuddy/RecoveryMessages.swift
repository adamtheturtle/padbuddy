import Foundation

nonisolated enum RecoveryMessages {
    static var interviewEndedRefreshFailed: String {
        String(localized: """
        The interview was ended, but the latest pad details could not be refreshed. \
        Reload to confirm the final timestamp.
        """, table: "RecoveryMessages")
    }

    static var invalidCreatedPad: String {
        String(localized: "The created pad returned an invalid identifier.", table: "RecoveryMessages")
    }

    static var unavailableQuestion: String {
        String(localized: "The selected question is no longer available.", table: "RecoveryMessages")
    }
}
