import Foundation

extension PadUpdateNotifier {
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
