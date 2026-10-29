nonisolated enum QuestionInstructionPreview {
    static let maximumParts = 16
    static let maximumScalars = 16384

    /// Inline saves resend the complete instruction list. Require every part to
    /// fit before offering an editor, so saving a preview never replaces full text.
    static func canEdit(_ instructions: [CandidateInstruction]) -> Bool {
        guard instructions.count <= maximumParts else { return false }

        return instructions.allSatisfy {
            $0.instructions.unicodeScalars.prefix(maximumScalars + 1).count <= maximumScalars
                && ($0.name?.unicodeScalars.prefix(201).count ?? 0) <= 200
        }
    }
}
