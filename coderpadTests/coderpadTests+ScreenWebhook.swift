//
//  coderpadTests+ScreenWebhook.swift
//  coderpadTests
//

@testable import CoderPad
import Testing

@Suite("Screen webhook validation")
struct ScreenWebhookValidationTests {
    @Test(arguments: [
        "", "http://example.com/hook", "https://localhost/hook",
        "https://127.0.0.1/hook", "https://user:secret@example.com/hook",
        "https://example.com/hook#fragment"
    ])
    func `setter rejects unsafe callback URLs before transport`(url: String) async {
        #expect(ScreenClient.normalizedWebhookURL(url) == nil)
        do {
            try await screenClient().setWebhookURL(url)
            Issue.record("Expected an unsafe webhook URL to throw")
        } catch let error as CoderPadError {
            #expect(error.description.contains("public HTTPS URL"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `setter trims a safe public HTTPS callback`() async throws {
        #expect(ScreenClient.normalizedWebhookURL("  https://coderpad.io/hook?token=1\n")
            == "https://coderpad.io/hook?token=1")
        try await screenClient().setWebhookURL("  https://coderpad.io/hook?token=1\n")
    }

    @Test
    func `getter validation accepts absence and normalizes a safe callback`() throws {
        #expect(try ScreenClient.validatedWebhookURL(nil) == nil)
        #expect(try ScreenClient.validatedWebhookURL(" https://coderpad.io/hook ")
            == "https://coderpad.io/hook")
    }

    @Test(arguments: ["", "not a URL", "http://example.com", "https://localhost/hook"])
    func `getter validation rejects malformed server configuration`(url: String) {
        #expect(throws: CoderPadError.self) {
            try ScreenClient.validatedWebhookURL(url)
        }
    }
}
