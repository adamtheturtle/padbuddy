import Foundation

nonisolated struct ScreenTagPresentation {
    let text: String
    let omitted: Bool

    init(_ tags: [String]) {
        let visible = tags.prefix(16)
        let labels = visible.map { ExternalText.singleLine($0, limit: 80) }.filter { !$0.isEmpty }
        text = labels.joined(separator: ", ")
        omitted = tags.count > 16 || labels.count != visible.count
            || visible.contains { $0.unicodeScalars.prefix(81).count > 80 }
    }
}
