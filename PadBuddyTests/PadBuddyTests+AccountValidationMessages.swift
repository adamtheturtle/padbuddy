//
//  PadBuddyTests+AccountValidationMessages.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Testing

@Suite("Account validation messages")
@MainActor
struct AccountValidationMessageTests {
    private func editor() -> AccountEditor {
        AccountEditor(
            initial: Account(name: "", apiKey: "test-key"),
            onSave: { _ in true },
            onCancel: {}
        )
    }

    @Test
    func `validation 404 points at the Server URL instead of saying retry`() {
        let message = editor().friendlyValidationMessage(for: CoderPadError.http(404, "Not Found"))

        #expect(message.contains("Server URL"))
        #expect(message.contains("https://app.coderpad.io"))
        #expect(!message.contains("Try again in a moment"))
    }

    @Test
    func `validation includes API message for unexpected HTTP status`() {
        let body = #"{"message":"API access is disabled for this organization"}"#
        let message = editor().friendlyValidationMessage(for: CoderPadError.http(451, body))

        #expect(message.contains("API access is disabled for this organization"))
        #expect(message.contains("could not validate this key"))
    }

    @Test
    func `validation bounds and sanitizes server messages`() {
        let longMessage = String(repeating: "a", count: 400)
        let longBody = #"{"message":"\#(longMessage)"}"#
        let bounded = editor().friendlyValidationMessage(for: CoderPadError.http(451, longBody))
        #expect(bounded.count < 320)
        #expect(bounded.contains("…"))

        let whitespace = editor().friendlyValidationMessage(
            for: CoderPadError.http(451, #"{"message":"  Access\n\t is disabled  "}"#)
        )
        #expect(whitespace.contains("Access is disabled"))
    }

    @Test(arguments: [
        #"{"error":"A generic gateway error"}"#,
        #"{"message":"<html>gateway failure</html>"}"#,
        #"{"message":"gateway\u001B[31m failure"}"#
    ])
    func `validation rejects untrusted message shapes`(body: String) {
        let message = editor().friendlyValidationMessage(for: CoderPadError.http(451, body))

        #expect(message.contains("HTTP 451"))
        #expect(!message.contains("gateway"))
    }

    @Test
    func `validation does not parse oversized response bodies`() {
        let body = #"{"message":"# + String(repeating: "x", count: 17000) + #""}"#
        let message = editor().friendlyValidationMessage(for: CoderPadError.http(451, body))

        #expect(message.contains("HTTP 451"))
        #expect(message.count < 100)
    }
}
