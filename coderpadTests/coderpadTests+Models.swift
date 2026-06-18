//
//  coderpadTests+Models.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import SwiftUI
import Testing

@Suite("Question sort field/direction")
struct QuestionSortTests {
    @Test func `each sort maps to the expected field`() {
        #expect(QuestionSort.lastUsedDesc.field == .lastUsed)
        #expect(QuestionSort.lastUsedAsc.field == .lastUsed)
        #expect(QuestionSort.usedDesc.field == .used)
        #expect(QuestionSort.usedAsc.field == .used)
        #expect(QuestionSort.titleAsc.field == .title)
        #expect(QuestionSort.titleDesc.field == .title)
    }

    @Test func `directions list the field's two sorts, default first`() {
        #expect(QuestionSort.directions(for: .lastUsed).map(\.sort) == [.lastUsedDesc, .lastUsedAsc])
        #expect(QuestionSort.directions(for: .used).map(\.sort) == [.usedDesc, .usedAsc])
        #expect(QuestionSort.directions(for: .title).map(\.sort) == [.titleAsc, .titleDesc])
    }

    @Test func `withField keeps the current direction slot`() {
        // Slot 0 (default) stays slot 0 across fields.
        #expect(QuestionSort.lastUsedDesc.withField(.title) == .titleAsc)
        #expect(QuestionSort.titleAsc.withField(.used) == .usedDesc)
        // Slot 1 (reverse) stays slot 1.
        #expect(QuestionSort.lastUsedAsc.withField(.title) == .titleDesc)
        #expect(QuestionSort.titleDesc.withField(.lastUsed) == .lastUsedAsc)
        // Switching to the same field is a no-op.
        #expect(QuestionSort.usedAsc.withField(.used) == .usedAsc)
    }
}

@Suite("Language helpers")
struct LanguageHelperTests {
    @Test(arguments: [
        ("python3", "Python 3"),
        ("python2", "Python 2"),
        ("javascript", "JavaScript"),
        ("typescript", "TypeScript"),
        ("nodejs", "Node.js"),
        ("cpp", "C++"),
        ("csharp", "C#"),
        ("objective-c", "Objective-C"),
        ("postgresql", "PostgreSQL"),
        ("fsharp", "F#"),
        ("julia", "Julia"),
        ("markdown", "Markdown"),
        ("solidity", "Solidity"),
        ("tcl", "Tcl"),
        ("verilog", "Verilog")
    ])
    func `languageDisplayName maps known codes to friendly names`(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }

    @Test(arguments: [
        ("multifile_java", "Java Project"),
        ("Multifile_java", "Java Project"),
        ("multifile_python", "Python Project"),
        ("multifile_python3", "Python 3 Project"),
        ("multifile_nodejs", "Node.js Project")
    ])
    func `languageDisplayName names multifile project environments`(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }

    @Test(arguments: [
        ("zig", "Zig"),
        ("", "")
    ])
    func `languageDisplayName capitalizes unknown codes`(code: String, expected: String) {
        #expect(code.languageDisplayName == expected)
    }
}

@Suite("Color hex")
struct ColorHexTests {
    @Test func `hex string round-trips through Color`() {
        let color = Color(hex: "#3478F6")
        #expect(color != nil)
        #expect(color?.hexString == "#3478F6")
    }

    @Test func `a leading hash is optional`() {
        #expect(Color(hex: "3478F6")?.hexString == "#3478F6")
    }

    @Test func `malformed hex returns nil`() {
        #expect(Color(hex: "nope") == nil)
        #expect(Color(hex: "#12345") == nil)
        #expect(Color(hex: "") == nil)
    }
}

@Suite("Quota decoder")
struct QuotaDecoderTests {
    @Test
    func `parses dates with timezone offset and fractional seconds`() throws {
        let json = """
        {
          "status": "OK",
          "trial_expires_at": "2025-04-24T17:00:00.000-07:00",
          "pads_used": 57,
          "quota_reset_at": "2026-05-29T00:05:00.000-07:00",
          "unlimited": true,
          "overages_enabled": false
        }
        """
        let quota = try CoderPadClient.decoder.decode(Quota.self, from: Data(json.utf8))
        #expect(quota.padsUsed == 57)
        #expect(quota.unlimited == true)
        #expect(quota.overagesEnabled == false)
        #expect(quota.trialExpiresAt != nil)
        #expect(quota.quotaReset != nil)
    }
}

@Suite("Pad request execution_enabled encoding")
struct PadExecutionEncodingTests {
    private func json(_ value: some Encodable) throws -> String {
        try #require(String(bytes: CoderPadClient.encoder.encode(value), encoding: .utf8))
    }

    @Test
    func `pad creation encodes execution_enabled as a JSON string, not a boolean`() throws {
        // CoderPad's pad API ignores a real boolean here and only honors the string
        // form, contrary to its published docs. See issue #305.
        let enabled = try json(PadCreate(language: "python3", executionEnabled: true))
        #expect(enabled.contains(#""execution_enabled":"true""#))
        #expect(!enabled.contains(#""execution_enabled":true"#))

        let disabled = try json(PadCreate(executionEnabled: false))
        #expect(disabled.contains(#""execution_enabled":"false""#))
    }

    @Test
    func `pad update encodes execution_enabled as a JSON string`() throws {
        let body = try json(PadUpdate(id: "ABC", executionEnabled: true))
        #expect(body.contains(#""execution_enabled":"true""#))
        #expect(!body.contains(#""execution_enabled":true"#))
    }

    @Test
    func `a nil execution flag is omitted entirely`() throws {
        #expect(try !json(PadUpdate(id: "ABC", executionEnabled: nil)).contains("execution_enabled"))
        #expect(try !json(PadCreate(language: "python3")).contains("execution_enabled"))
    }

    @Test
    func `execution_enabled decodes from either the string or the boolean shape`() throws {
        // The string form we now send.
        let stringForm = Data(#"{"id":"ABC","execution_enabled":"true"}"#.utf8)
        #expect(try JSONDecoder().decode(PadUpdate.self, from: stringForm).executionEnabled == true)
        // The boolean shape (older payloads / the published-docs shape) still decodes.
        let boolForm = Data(#"{"id":"ABC","execution_enabled":false}"#.utf8)
        #expect(try JSONDecoder().decode(PadUpdate.self, from: boolForm).executionEnabled == false)
    }
}

@Suite("CoderPadError messages")
struct CoderPadErrorMessageTests {
    @Test
    func `HTTP errors never leak the raw response body into the message`() throws {
        let error = CoderPadError.http(404, #"{"status":404,"error":"Not Found"}"#)
        let message = try #require(error.errorDescription)
        // The old message dumped the JSON verbatim; the new one must not.
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
    func `transport failures map to plain-language, actionable messages`() {
        #expect(CoderPadError.network(URLError(.notConnectedToInternet)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.networkConnectionLost)).errorDescription?.contains("offline") == true)
        #expect(CoderPadError.network(URLError(.timedOut)).errorDescription?.contains("timed out") == true)
        #expect(
            CoderPadError.network(URLError(.cannotConnectToHost)).errorDescription?.contains("reach CoderPad") == true
        )
        #expect(CoderPadError.network(URLError(.cannotFindHost)).errorDescription?.contains("reach CoderPad") == true)
        // An unmapped code still gets a useful, non-empty fallback (not a raw URLError dump).
        let fallback = CoderPadError.network(URLError(.badServerResponse)).errorDescription ?? ""
        #expect(fallback.contains("network error"))
        #expect(!fallback.contains("Error Domain"))
    }
}
