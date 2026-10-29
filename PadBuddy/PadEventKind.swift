import Foundation

nonisolated enum PadEventKind {
    static func normalized(_ raw: String) -> String {
        let bounded = ExternalText.singleLine(raw, limit: 64)
        let folded = String(bounded.lowercased().unicodeScalars.prefix(64))
        // An oversized unknown kind must not become a known kind by truncation.
        return folded + (raw.unicodeScalars.prefix(65).count > 64 ? "…" : "")
    }
}
