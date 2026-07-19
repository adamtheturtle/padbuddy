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

@Suite("Favorite drop de-duplication (#2275)")
struct FavoriteDropIdentityTests {
    @Test
    func `the same item from two drags has one identity`() {
        // The title is deliberately excluded: the same favourite dragged from two
        // lists can carry two spellings of its name, and both are the same item.
        let account = UUID()
        #expect(Sidebar.identity(of: .pad(account: account, id: "abc123", title: "One"))
            == Sidebar.identity(of: .pad(account: account, id: "abc123", title: "Another")))
    }

    @Test
    func `a different account or item has a different identity`() {
        let account = UUID()
        let other = UUID()
        let base = Sidebar.identity(of: .pad(account: account, id: "abc123", title: "One"))
        #expect(base != Sidebar.identity(of: .pad(account: other, id: "abc123", title: "One")))
        #expect(base != Sidebar.identity(of: .pad(account: account, id: "def456", title: "One")))
    }

    @Test
    func `a pad and a question with matching ids differ`() {
        let account = UUID()
        #expect(Sidebar.identity(of: .pad(account: account, id: "42", title: "P"))
            != Sidebar.identity(of: .question(account: account, id: 42, title: "Q")))
    }
}

@Suite("Account footer display names (#2233)")
struct AccountFooterDisplayNameTests {
    @MainActor
    private func account(name: String, email: String) -> Account {
        Account(name: name, apiKey: "k", userEmail: email)
    }

    @MainActor
    @Test
    func `a real name is used as-is`() {
        #expect(AccountFooter.displayName(for: account(name: "Fawlty Towers", email: "b@ft.co.uk"))
            == "Fawlty Towers")
    }

    @MainActor
    @Test
    func `a blank or whitespace-only name falls back to the address`() {
        // A whitespace-only name left the trigger and its menu row unidentifiable.
        #expect(AccountFooter.displayName(for: account(name: "", email: "b@ft.co.uk")) == "b@ft.co.uk")
        #expect(AccountFooter.displayName(for: account(name: "   ", email: "b@ft.co.uk")) == "b@ft.co.uk")
        #expect(AccountFooter.displayName(for: account(name: "\n\t", email: "b@ft.co.uk")) == "b@ft.co.uk")
    }

    @MainActor
    @Test
    func `a name is trimmed`() {
        #expect(AccountFooter.displayName(for: account(name: "  Fawlty  ", email: "b@ft.co.uk")) == "Fawlty")
    }

    @MainActor
    @Test
    func `with neither a name nor an address there is still a label`() {
        #expect(!AccountFooter.displayName(for: account(name: " ", email: " ")).isEmpty)
    }
}

#if canImport(FoundationModels)
    @Suite("Code explainer input bounds (#1719, #2222)")
    struct PadCodeExplainerBoundsTests {
        @Test
        func `short ASCII source is unchanged`() {
            let code = "func main() {}\n"
            #expect(PadCodeExplainer.boundedCode(code) == code)
        }

        @Test
        func `the character cap applies first`() {
            let code = String(repeating: "a", count: PadCodeExplainer.maxCodeCharacters * 2)
            #expect(PadCodeExplainer.boundedCode(code).count == PadCodeExplainer.maxCodeCharacters)
        }

        @Test
        func `dense non-ascii source is bounded by bytes, not characters`() {
            // Under the character cap but well over the byte cap: each emoji is four
            // UTF-8 bytes, so 5000 of them is 20000 bytes (#1719).
            let code = String(repeating: "😀", count: 5000)
            let bounded = PadCodeExplainer.boundedCode(code)
            #expect(bounded.utf8.count <= PadCodeExplainer.maxCodeUTF8Bytes)
            #expect(!bounded.isEmpty)
        }

        @Test
        func `truncation never splits a character`() {
            // The byte cut can land mid-scalar; the result must still be valid text
            // rather than replacement characters or an empty string (#2222).
            for filler in ["😀", "é", "日", "🇬🇧"] {
                let code = String(repeating: filler, count: 6000)
                let bounded = PadCodeExplainer.boundedCode(code)
                #expect(bounded.utf8.count <= PadCodeExplainer.maxCodeUTF8Bytes)
                #expect(!bounded.contains("\u{FFFD}"))
                #expect(bounded.allSatisfy { String($0) == filler })
            }
        }

        @Test
        func `a result at the byte cap is as long as it can be`() {
            // Guards against backing off too far: the old loop cut to 3/4 repeatedly.
            let code = String(repeating: "😀", count: 5000)
            let bounded = PadCodeExplainer.boundedCode(code)
            #expect(bounded.utf8.count > PadCodeExplainer.maxCodeUTF8Bytes - 8)
        }

        @Test
        func `empty source stays empty`() {
            #expect(PadCodeExplainer.boundedCode("").isEmpty)
        }
    }
#endif
