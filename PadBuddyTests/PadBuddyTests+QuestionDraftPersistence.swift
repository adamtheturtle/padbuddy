import Foundation
@testable import PadBuddy
import Testing

@Suite("Question creation draft persistence")
struct QuestionDraftPersistenceTests {
    @Test
    func `oversized persisted drafts are bounded before restoration`() throws {
        let oversized = String(repeating: "x", count: NewQuestionSheet.Limits.longForm + 1)
        let draft = QuestionCreationDraft(
            title: oversized, language: oversized, description: oversized,
            instructions: oversized, solution: oversized, padType: oversized,
            draftPrompt: oversized, selectedSection: oversized,
            starterFiles: (0 ... NewQuestionSheet.Limits.starterFiles).map { index in
                QuestionStarterFileDraft(path: "\(index)-\(oversized)", contents: oversized)
            }
        )

        let restored = NewQuestionSheet.normalizedRestoredDraft(draft)

        #expect(restored.title.count == NewQuestionSheet.Limits.title)
        #expect(restored.language == "python3")
        #expect(restored.description.count == NewQuestionSheet.Limits.longForm)
        #expect(restored.instructions.count == NewQuestionSheet.Limits.longForm)
        #expect(restored.solution.count == NewQuestionSheet.Limits.longForm)
        #expect(restored.padType == QuestionPadType.fallback)
        #expect(restored.draftPrompt.count == NewQuestionSheet.Limits.draftPrompt)
        #expect(restored.selectedSection == QuestionDraftSection.instructions.rawValue)
        let files = try #require(restored.starterFiles)
        #expect(files.count == NewQuestionSheet.Limits.starterFiles)
        #expect(files.allSatisfy { $0.path.count == NewQuestionSheet.Limits.starterFilePath })
        #expect(files.allSatisfy { $0.contents.count == NewQuestionSheet.Limits.longForm })
    }
}
