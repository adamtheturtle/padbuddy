import Foundation
@testable import PadBuddy
import Testing

@Suite("Question creation draft persistence")
struct QuestionDraftPersistenceTests {
    @Test
    func `corrupt draft is cleared once and a subsequent clean save loads`() throws {
        let suite = "QuestionDraftPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = UUID()
        defaults.set(Data("not-json".utf8), forKey: "creationDraft.v1.question.\(account.uuidString)")

        let first = CreationDraftStore.load(
            QuestionCreationDraft.self, kind: "question", account: account, defaults: defaults
        )
        guard case .corrupt = first else {
            Issue.record("The invalid blob should be reported as corrupt")
            return
        }

        let second = CreationDraftStore.load(
            QuestionCreationDraft.self, kind: "question", account: account, defaults: defaults
        )
        guard case .missing = second else {
            Issue.record("The corrupt blob should have been removed")
            return
        }

        let clean = QuestionCreationDraft(
            title: "Clean", language: "python3", description: "", instructions: "",
            solution: "", padType: "live", draftPrompt: "", selectedSection: "instructions"
        )
        CreationDraftStore.save(clean, kind: "question", account: account, defaults: defaults)
        let saved = CreationDraftStore.load(
            QuestionCreationDraft.self, kind: "question", account: account, defaults: defaults
        )
        guard case let .value(restored) = saved else {
            Issue.record("A clean save should load after recovery")
            return
        }

        #expect(restored == clean)
    }

    @Test
    func `oversized persisted drafts are bounded before restoration`() throws {
        let oversized = String(repeating: "x", count: NewQuestionSheet.Limits.longForm + 1)
        let draft = QuestionCreationDraft(
            title: oversized, language: oversized, description: oversized,
            instructions: oversized, solution: oversized, padType: oversized,
            draftPrompt: oversized, selectedSection: oversized,
            starterFiles: (0 ... QuestionStarterFileDraft.maximumCount).map { index in
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
        #expect(files.count == QuestionStarterFileDraft.maximumCount)
        #expect(files.allSatisfy { $0.path.count == NewQuestionSheet.Limits.starterFilePath })
        #expect(files.allSatisfy {
            $0.contents.utf8.count <= QuestionStarterFileDraft.maximumContentBytes
        })
        #expect(files.reduce(0) { $0 + $1.contents.utf8.count }
            <= QuestionStarterFileDraft.maximumAggregateContentBytes)
    }
}
