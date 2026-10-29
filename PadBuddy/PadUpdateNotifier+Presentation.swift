import Foundation

struct PadNotificationPayload {
    let count: Int
    let title: String
    let body: String
    let url: String?
}

extension PadUpdateNotifier {
    static func notificationPayload(changes: [PadChange], accountID: UUID?) -> PadNotificationPayload {
        if changes.count == 1, let change = changes.first {
            let url = change.pad.id.utf8.count <= 256
                ? notificationURL(padID: change.pad.id, accountID: accountID)?.absoluteString : nil
            return PadNotificationPayload(
                count: 1, title: notificationPadTitle(change.pad.title), body: change.kind.detail, url: url
            )
        }
        return PadNotificationPayload(
            count: changes.count, title: String(localized: "Pads updated"), body: summary(of: changes),
            url: padsNotificationURL(accountID: accountID)?.absoluteString ?? "com.adamdangoor.padbuddy://pads"
        )
    }

    nonisolated static let maximumTitleScalars = 128

    /// Bound before normalization so notification construction never copies or
    /// scans an entire oversized remote title.
    static func notificationPadTitle(_ raw: String) -> String {
        let title = notificationAccountName(raw)
        return title.isEmpty ? String(localized: "Untitled pad") : title
    }

    static func notificationAccountName(_ raw: String) -> String {
        let bounded = String(raw.unicodeScalars.prefix(maximumTitleScalars).map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: " "
            default: Character(scalar)
            }
        })
        return bounded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
