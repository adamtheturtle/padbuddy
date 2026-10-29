nonisolated enum QuestionMetadataPresentation {
    static func label(_ raw: String?) -> String? {
        let label = ExternalText.singleLine(raw ?? "", limit: 200)
        return label.isEmpty ? nil : label
    }
}
