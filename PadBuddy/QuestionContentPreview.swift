import Foundation
import SwiftUI

nonisolated struct QuestionContentPreview {
    static let maximumCopyBytes = 64 * 1024
    let text: String
    let isTruncated: Bool

    init(_ raw: String, limit: Int = 2048) {
        let limit = min(max(0, limit), 65536)
        let scalars = Array(raw.unicodeScalars.prefix(limit + 1))
        isTruncated = scalars.count > limit
        text = String(scalars.prefix(limit).map { scalar -> Character in
            if scalar == "\n" || scalar == "\t" {
                return Character(scalar)
            }
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: return " "
            default: return Character(scalar)
            }
        }) + (isTruncated ? "…" : "")
    }

    static func canCopyFullValue(_ raw: String) -> Bool {
        raw.utf8.prefix(maximumCopyBytes + 1).count <= maximumCopyBytes
    }
}

struct QuestionPreviewNotice: View {
    var body: some View {
        Text(String(localized: "Preview truncated.", table: "QuestionPreviews"))
            .font(.caption).foregroundStyle(.secondary)
    }
}

nonisolated struct QuestionArgumentPreview {
    let text: String
    let isTruncated: Bool

    init(_ arguments: [String]?) {
        guard let arguments, !arguments.isEmpty else {
            text = String(localized: "None")
            isTruncated = false
            return
        }

        let visible = arguments.prefix(16).map { QuestionContentPreview($0, limit: 128) }
        text = visible.map(\.text).joined(separator: ", ")
        isTruncated = arguments.count > 16 || visible.contains(where: \.isTruncated)
    }
}
