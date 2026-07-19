//
//  coderpadTests+CoderPadErrorMessages.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

@Suite("CoderPadError messages")
struct CoderPadErrorMessageTests {
    @Test
    func `HTTP errors never leak the raw response body into the message`() throws {
        let error = CoderPadError.http(404, #"{"status":404,"error":"Not Found"}"#)
        let message = try #require(error.errorDescription)
        #expect(!message.contains("{"))
        #expect(!message.contains("status"))
        #expect(message.contains("deleted"))
    }

    @Test
    func `known status codes get a plain-language explanation`() {
        #expect(CoderPadError.http(401, "").errorDescription?.contains("API key") == true)
        #expect(CoderPadError.http(429, "").errorDescription?.contains("rate-limiting") == true)
        #expect(CoderPadError.http(503, "").errorDescription?.contains("server error") == true)
    }

    @Test
    func `an API-supplied message is preferred over a bare HTTP code`() {
        let error = CoderPadError.http(422, #"{"message":"Title can't be blank"}"#)
        #expect(error.errorDescription == "Title can't be blank")
    }

    @Test
    func `API messages are normalized and bounded before presentation`() throws {
        let long = String(repeating: "a", count: 500)
        let body = try #require(String(data: JSONSerialization.data(withJSONObject: [
            "message": "  Access\n\t denied\u{001B}\(long)  "
        ]), encoding: .utf8))
        let message = try #require(CoderPadError.http(422, body).errorDescription)

        #expect(message.hasPrefix("Access denied"))
        #expect(message.count == 300)
        #expect(message.hasSuffix("…"))
        #expect(!message.contains("\u{001B}"))
    }

    @Test(arguments: [
        #"{"error":{"message":"Nested explanation"}}"#,
        #"{"errors":[{"detail":"Array explanation"}]}"#
    ])
    func `documented nested API envelopes surface a safe explanation`(body: String) {
        let message = CoderPadError.http(422, body).errorDescription
        #expect(message?.contains("explanation") == true)
    }

    @Test
    func `arbitrary deeply nested JSON falls back safely`() {
        let body = #"{"payload":{"nested":{"message":"Do not crawl me"}}}"#
        #expect(CoderPadError.http(422, body).errorDescription == "The request failed (HTTP 422).")
    }

    @Test
    func `transport failures map to plain-language, actionable messages`() {
        #expect(CoderPadError.network(URLError(.notConnectedToInternet)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.networkConnectionLost)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.timedOut)).errorDescription?.contains("timed out") == true)
        #expect(
            CoderPadError.network(URLError(.cannotConnectToHost)).errorDescription?.contains("reach CoderPad") == true
        )
        #expect(CoderPadError.network(URLError(.cannotFindHost)).errorDescription?.contains("reach CoderPad") == true)
        let fallback = CoderPadError.network(URLError(.badServerResponse)).errorDescription ?? ""
        #expect(fallback.contains("network error"))
        #expect(!fallback.contains("Error Domain"))
    }
}
