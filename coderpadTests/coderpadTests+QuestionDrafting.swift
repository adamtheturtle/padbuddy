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
            #expect(!PadCodeExplainer.boundedExcerpt(code).isTruncated)
        }

        @Test
        func `the character cap applies first`() {
            let code = String(repeating: "a", count: PadCodeExplainer.maxCodeCharacters * 2)
            #expect(PadCodeExplainer.boundedCode(code).count == PadCodeExplainer.maxCodeCharacters)
            #expect(PadCodeExplainer.boundedExcerpt(code).isTruncated)
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

@Suite("Markdown inline escaping (#2216)")
struct MarkdownInlineEscapingTests {
    @Test
    func `special characters are escaped`() {
        #expect(markdownInlineEscaped("a*b_c") == "a\\*b\\_c")
        #expect(markdownInlineEscaped("[x](y)") == "\\[x\\](y)")
        #expect(markdownInlineEscaped("a|b") == "a\\|b")
        #expect(markdownInlineEscaped("back\\slash") == "back\\\\slash")
    }

    @Test
    func `every newline form becomes a single space`() {
        // CRLF is one Character in Swift, so the single-pass loop must not emit two
        // spaces for it the way three sequential replacements did not (#2216).
        #expect(markdownInlineEscaped("a\r\nb") == "a b")
        #expect(markdownInlineEscaped("a\nb") == "a b")
        #expect(markdownInlineEscaped("a\rb") == "a b")
        #expect(markdownInlineEscaped("a\n\nb") == "a  b")
    }

    @Test
    func `ordinary text is unchanged`() {
        #expect(markdownInlineEscaped("Two Sum with Constraints") == "Two Sum with Constraints")
        #expect(markdownInlineEscaped("").isEmpty)
    }

    @Test
    func `newlines and specials combine`() {
        #expect(markdownInlineEscaped("a*b\nc_d") == "a\\*b c\\_d")
    }
}

@Suite("Widget per-account filenames (#2184)")
struct WidgetFileSafeAccountTests {
    @Test
    func `a uuid string is unchanged`() {
        let id = UUID().uuidString
        #expect(WidgetSharedStore.fileSafeAccount(id) == id)
    }

    @Test
    func `path separators cannot escape the naming scheme`() {
        #expect(!WidgetSharedStore.fileSafeAccount("../../etc/passwd").contains("/"))
        #expect(!WidgetSharedStore.fileSafeAccount("../../etc/passwd").contains("."))
        #expect(!WidgetSharedStore.fileSafeAccount("a\\b").contains("\\"))
        #expect(!WidgetSharedStore.fileSafeAccount("a:b").contains(":"))
    }

    @Test
    func `only letters, digits and hyphens survive`() {
        #expect(WidgetSharedStore.fileSafeAccount("ab-12") == "ab-12")
        #expect(WidgetSharedStore.fileSafeAccount("a b") == "a-b")
        #expect(WidgetSharedStore.fileSafeAccount("é") == "-")
        #expect(WidgetSharedStore.fileSafeAccount("a\u{0000}b") == "a-b")
    }

    @Test
    func `length is preserved so distinct ids stay distinct`() {
        // Folding to "-" can collide two odd identifiers, but must not truncate.
        #expect(WidgetSharedStore.fileSafeAccount("abc/def").count == 7)
    }
}

@Suite("Open Pad by URL validation (#2163, #2164, #2165)")
struct OpenPadURLParsingTests {
    private func failure(_ raw: String) -> String? {
        guard case let .failure(reason) = OpenPadURLSheet.parse(raw) else { return nil }

        return reason
    }

    private func url(_ raw: String) -> URL? {
        guard case let .success(url) = OpenPadURLSheet.parse(raw) else { return nil }

        return url
    }

    @Test
    func `a pad url is accepted`() {
        #expect(url("https://app.coderpad.io/abc12345") != nil)
        #expect(url("  https://app.coderpad.io/abc12345/playback  ") != nil)
    }

    @Test
    func `blank input reports no problem to show`() {
        #expect(failure("")?.isEmpty == true)
        #expect(failure("   ")?.isEmpty == true)
    }

    @Test
    func `non-web schemes are refused`() {
        // The sheet hands its result to the browser, so file:// and custom schemes
        // must not reach it (#2163).
        #expect(url("file:///etc/passwd") == nil)
        #expect(url("coderpad://pad/abc12345") == nil)
        #expect(url("javascript:alert(1)") == nil)
        #expect(failure("file:///etc/passwd")?.isEmpty == false)
    }

    @Test
    func `embedded credentials are refused`() {
        // Pasted secrets would land in browser history and be sent to the host (#2164).
        #expect(url("https://user:secret@app.coderpad.io/abc12345") == nil)
        #expect(url("https://user@app.coderpad.io/abc12345") == nil)
    }

    @Test
    func `non-pad paths are refused`() {
        #expect(url("https://app.coderpad.io/login") == nil)
        #expect(url("https://app.coderpad.io") == nil)
    }

    @Test
    func `every refusal explains itself`() {
        // The point of #2165: Open is not just silently disabled.
        for raw in ["file:///x", "https://user:p@app.coderpad.io/abc12345",
                    "https://app.coderpad.io/login", "not a url at all"] {
            let reason = failure(raw)
            #expect(reason?.isEmpty == false, "\(raw) should explain itself")
        }
    }
}

@Suite("Browser opener URL gating (#2158)")
struct BrowserOpenGatingTests {
    @Test
    func `web addresses are openable`() throws {
        #expect(try BrowserSettings.isOpenableWebURL(#require(URL(string: "https://app.coderpad.io/abc"))))
        #expect(try BrowserSettings.isOpenableWebURL(#require(URL(string: "http://pads.example.com:8080/abc"))))
    }

    @Test
    func `non-web schemes are refused`() throws {
        // A call site holding one of these would otherwise have it launched under the
        // user's browser preference (#2158).
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "file:///etc/passwd"))))
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "coderpad://pad/abc"))))
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "ftp://example.com/x"))))
    }

    @Test
    func `a hostless address is refused`() throws {
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "https:///path"))))
    }

    @Test
    func `a missing selected browser requires an explicit fallback warning`() throws {
        let installed = try #require(URL(string: "file:///Applications/Browser.app"))
        #expect(BrowserSettings.usesUnexpectedBrowserFallback(
            requestedBundleID: "com.example.browser", chosenAppURL: nil
        ))
        #expect(!BrowserSettings.usesUnexpectedBrowserFallback(
            requestedBundleID: "com.example.browser", chosenAppURL: installed
        ))
        #expect(!BrowserSettings.usesUnexpectedBrowserFallback(requestedBundleID: nil, chosenAppURL: nil))
    }
}
