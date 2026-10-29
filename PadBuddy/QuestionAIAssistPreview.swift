import Foundation

nonisolated enum QuestionAIAssistPreview {
    static func make(_ raw: String?) -> QuestionContentPreview? {
        guard let raw else { return nil }

        let preview = QuestionContentPreview(raw, limit: 16384)
        guard preview.isTruncated || !preview.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return preview
    }
}
