import Foundation

nonisolated enum ExternalText {
    /// Bound before normalization so oversized external input is never copied in full.
    static func singleLine(_ raw: String, limit: Int) -> String {
        let bounded = String(raw.unicodeScalars.prefix(max(0, limit)).map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: " "
            default: Character(scalar)
            }
        })
        return bounded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
