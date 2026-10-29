import Foundation

nonisolated enum ScreenInvitationDuplicatePolicy: String, CaseIterable, Identifiable {
    case serviceDefault
    case prevent
    case allow

    var id: Self {
        self
    }

    var allowDuplicateInvitations: Bool? {
        switch self {
        case .serviceDefault: nil
        case .prevent: false
        case .allow: true
        }
    }

    var title: String {
        switch self {
        case .serviceDefault: String(localized: "Default (allow duplicates)")
        case .prevent: String(localized: "Prevent duplicate invitations")
        case .allow: String(localized: "Allow duplicate invitations")
        }
    }
}
