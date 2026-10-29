import Foundation

nonisolated enum RecoveryMessages {
    static var unavailableQuestion: String {
        String(localized: "The selected question is no longer available.", table: "RecoveryMessages")
    }
}
