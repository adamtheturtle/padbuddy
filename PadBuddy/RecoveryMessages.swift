import Foundation

nonisolated enum RecoveryMessages {
    static var invalidCreatedPad: String {
        String(localized: "The created pad returned an invalid identifier.", table: "RecoveryMessages")
    }

    static var unavailableQuestion: String {
        String(localized: "The selected question is no longer available.", table: "RecoveryMessages")
    }
}
