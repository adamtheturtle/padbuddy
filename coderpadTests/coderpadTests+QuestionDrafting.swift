//
//  coderpadTests+QuestionDrafting.swift
//  coderpadTests
//
//  New Question sheet and drafter tests, split from
//  coderpadTests+NewPadNormalization.swift to keep both files under the
//  file-length limit.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("New Question sheet input handling (#2335, #2340)")
struct NewQuestionSheetInputTests {
    @Test
    func `an unrecognized interview type falls back to the default`() {
        #expect(QuestionPadType.normalized("not-a-type") == QuestionPadType.fallback)
        #expect(QuestionPadType.normalized("") == QuestionPadType.fallback)
        #expect(QuestionPadType.normalized(InterviewType.takeHome.rawValue)
            == InterviewType.takeHome.rawValue)
    }

    @Test
    func `the create body derives both type fields from the same value`() {
        // An unrecognized padType used to be sent verbatim while takeHome fell to
        // false, so the payload described two different things (#2335).
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: "Two Sum", language: "python3", description: "", instructions: "",
            solution: "", padType: "nonsense"
        ))
        #expect(body.padType == QuestionPadType.fallback)
        #expect(body.takeHome == (QuestionPadType.fallback == InterviewType.takeHome.rawValue))
    }

    @Test
    func `an oversized title is bounded in the create body`() {
        let body = NewQuestionSheet.normalizedCreateBody(NewQuestionSheet.CreateDraft(
            title: String(repeating: "a", count: 5000), language: "python3",
            description: "", instructions: "", solution: "", padType: "live"
        ))
        #expect(body.title.count == NewQuestionSheet.Limits.title)
    }

    @Test
    func `draft text keeps newlines but drops other control characters`() {
        let raw = "  line one\n\tindented\u{0007}bell  "
        let cleaned = NewQuestionSheet.normalizedDraftText(raw, limit: 1000)
        #expect(cleaned == "line one\n\tindentedbell")
    }

    @Test
    func `draft text is bounded`() {
        let cleaned = NewQuestionSheet.normalizedDraftText(String(repeating: "x", count: 500), limit: 10)
        #expect(cleaned.count == 10)
    }
}

@Suite("Question drafter input and output handling (#2328, #2331)")
struct QuestionDrafterTests {
    @Test
    func `an empty or whitespace-only brief has nothing to draft from`() {
        #expect(QuestionDrafter.preparedPrompt("") == nil)
        #expect(QuestionDrafter.preparedPrompt("   \n ") == nil)
    }

    @Test
    func `a brief is trimmed and bounded`() {
        #expect(QuestionDrafter.preparedPrompt("  reverse a list  ") == "reverse a list")
        let long = String(repeating: "a", count: QuestionDrafter.maxPromptLength * 4)
        #expect(QuestionDrafter.preparedPrompt(long)?.count == QuestionDrafter.maxPromptLength)
    }

    @Test
    func `plain source passes through unchanged`() {
        #expect(QuestionDrafter.usableSolution("def f():\n    pass", language: "python3")
            == "def f():\n    pass")
    }

    @Test
    func `a matching fence is unwrapped`() {
        // CoderPad spells the language with a version suffix; a fence usually doesn't.
        #expect(QuestionDrafter.usableSolution("```python\ndef f():\n    pass\n```", language: "python3")
            == "def f():\n    pass")
    }

    @Test
    func `an untagged fence is unwrapped rather than rejected`() {
        #expect(QuestionDrafter.usableSolution("```\ndef f():\n    pass\n```", language: "python3")
            == "def f():\n    pass")
    }

    @Test
    func `a wrong-language fence is dropped instead of seeding the editor`() {
        // The model itself said this is Ruby; presenting it as the Python reference
        // solution would be wrong in a way an author might not read closely (#2331).
        #expect(QuestionDrafter.usableSolution("```ruby\nputs 1\n```", language: "python3").isEmpty)
    }
}

@Suite("Organization member preparation (#2273, #2380)")
struct OrganizationMemberPreparationTests {
    /// `Organization` is decode-only, so the demo server supplies a real one.
    private let client = CoderPadClient.mock(key: "test-\(UUID().uuidString)")

    @MainActor
    @Test
    func `members are de-duplicated and sorted once, independently of any query`() async throws {
        let org = try await client.organization()
        let prepared = OrganizationView.preparedUsers(org)

        // One row per distinct address, compared case-insensitively (#2380).
        let addresses = prepared.map { $0.email.lowercased() }
        #expect(Set(addresses).count == addresses.count)
        #expect(!prepared.isEmpty)

        // Sorted by display name, which is what the query filter then preserves
        // rather than re-establishing on every keystroke (#2273).
        let names = prepared.map { $0.name ?? $0.email }
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        #expect(names == sorted)
    }
}
