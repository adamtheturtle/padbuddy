import Foundation

extension PadUpdateNotifier {
    nonisolated static let maximumTitleScalars = 128

    /// Bound before normalization so notification construction never copies or
    /// scans an entire oversized remote title.
    static func notificationPadTitle(_ raw: String) -> String {
        let bounded = String(raw.unicodeScalars.prefix(maximumTitleScalars).map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: " "
            default: Character(scalar)
            }
        })
        let title = bounded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return title.isEmpty ? String(localized: "Untitled pad") : title
    }
}
