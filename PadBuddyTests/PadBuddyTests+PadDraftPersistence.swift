import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad creation draft persistence")
struct PadDraftPersistenceTests {
    @Test func `restored draft bounds text and rejects unsupported selections`() throws {
        let oversized = String(repeating: "x", count: 30000)
        let stored = PadCreationDraft(
            title: oversized, language: oversized, ownerEmail: oversized,
            isPrivate: true, executionEnabled: false, questionID: -1, teamID: oversized,
            access: PadAccessDraft(emails: oversized, timeLimit: oversized)
        )
        let decoded = try JSONDecoder().decode(PadCreationDraft.self, from: JSONEncoder().encode(stored))
        let restored = NewPadSheet.normalizedRestoredDraft(decoded)
        #expect(restored.title.count == 255)
        #expect(restored.ownerEmail.count == 254)
        #expect(restored.language == "python3")
        #expect(restored.questionID == nil)
        #expect(restored.teamID == nil)
        #expect(restored.access?.emails.count == 25500)
        #expect(restored.access?.timeLimit.count == 10)
        #expect(restored.isPrivate)
        #expect(!restored.executionEnabled)
    }

    @Test func `valid selections survive until prerequisite validation`() {
        let stored = PadCreationDraft(
            title: "Interview", language: "javascript", ownerEmail: "owner@example.com",
            isPrivate: false, executionEnabled: true, questionID: 42, teamID: "team-1"
        )
        #expect(NewPadSheet.normalizedRestoredDraft(stored) == stored)
    }
}
