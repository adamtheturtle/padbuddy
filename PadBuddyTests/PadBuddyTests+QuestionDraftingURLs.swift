//
//  PadBuddyTests+QuestionDraftingURLs.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

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
        #expect(url("com.adamdangoor.padbuddy://pad/abc12345") == nil)
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
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "com.adamdangoor.padbuddy://pad/abc"))))
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "ftp://example.com/x"))))
    }

    @Test
    func `a hostless address is refused`() throws {
        #expect(try !BrowserSettings.isOpenableWebURL(#require(URL(string: "https:///path"))))
    }

    @Test
    func `credential bearing web urls are refused`() throws {
        #expect(try !BrowserSettings.isOpenableWebURL(
            #require(URL(string: "https://user:secret@app.coderpad.io/pad"))
        ))
        #expect(try !BrowserSettings.isOpenableWebURL(
            #require(URL(string: "https://user@app.coderpad.io/pad"))
        ))
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
