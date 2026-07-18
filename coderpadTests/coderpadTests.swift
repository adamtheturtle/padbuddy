//
//  coderpadTests.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import SwiftUI
import Testing

@Suite("Pad decoder")
struct PadDecoderTests {
    private func decode(_ json: String) throws -> Pad {
        let data = Data(json.utf8)
        return try CoderPadClient.decoder.decode(Pad.self, from: data)
    }

    @Test
    func `decodes a full pad`() throws {
        let json = """
        {
          "id": "ABC123",
          "title": "Onsite",
          "state": "started",
          "owner_email": "owner@x.co",
          "language": "python3",
          "private": false,
          "execution_enabled": true,
          "participants": ["Jane", "Joe"],
          "url": "https://app.coderpad.io/ABC123",
          "playback": "https://app.coderpad.io/ABC123/playback",
          "created_at": "2026-06-09T23:02:35Z",
          "updated_at": "2026-06-09T23:09:23Z",
          "ended_at": null,
          "type": "live",
          "active_environment_id": 1,
          "pad_environment_ids": [1, 2],
          "question_ids": [42],
          "team": {"id": "team-1", "name": "Cursor"}
        }
        """
        let pad = try decode(json)
        #expect(pad.id == "ABC123")
        #expect(pad.title == "Onsite")
        #expect(pad.state == "started")
        #expect(pad.ownerEmail == "owner@x.co")
        #expect(pad.language == "python3")
        #expect(pad.participants == ["Jane", "Joe"])
        #expect(pad.padEnvironmentIDs == [1, 2])
        #expect(pad.questionIDs == [42])
        #expect(pad.team?.name == "Cursor")
        #expect(pad.executionEnabled == true)
        #expect(pad.isPrivate == false)
        #expect(pad.createdAt != nil)
    }

    @Test
    func `decodes a minimal pad with only an id`() throws {
        let pad = try decode(#"{"id": "X1"}"#)
        #expect(pad.id == "X1")
        #expect(pad.title.isEmpty)
        #expect(pad.state == "unknown")
        #expect(pad.ownerEmail.isEmpty)
        #expect(pad.participants.isEmpty)
        #expect(pad.padEnvironmentIDs.isEmpty)
        #expect(pad.questionIDs.isEmpty)
        #expect(pad.team == nil)
    }

    @Test
    func `tolerates null and missing fields`() throws {
        let json = """
        {
          "id": "X2",
          "title": null,
          "state": null,
          "owner_email": null,
          "language": null,
          "participants": null,
          "url": null,
          "playback": null,
          "created_at": null,
          "updated_at": null,
          "ended_at": null,
          "type": null,
          "execution_enabled": null,
          "private": null,
          "active_environment_id": null,
          "pad_environment_ids": null,
          "question_ids": null,
          "team": null
        }
        """
        let pad = try decode(json)
        #expect(pad.id == "X2")
        #expect(pad.title.isEmpty)
        #expect(pad.state == "unknown")
        #expect(pad.participants.isEmpty)
        #expect(pad.padEnvironmentIDs.isEmpty)
        #expect(pad.questionIDs.isEmpty)
    }

    @Test
    func `drops null entries inside the participants array`() throws {
        let json = """
        {
          "id": "X4",
          "participants": ["Jane", null, "Joe"]
        }
        """
        let pad = try decode(json)
        #expect(pad.participants == ["Jane", "Joe"])
    }

    @Test
    func `decodes both ISO8601 with Z and with offset+fractional seconds`() throws {
        let json = """
        {
          "id": "X3",
          "created_at": "2026-06-09T23:02:35Z",
          "updated_at": "2025-04-24T17:00:00.000-07:00"
        }
        """
        let pad = try decode(json)
        #expect(pad.createdAt != nil)
        #expect(pad.updatedAt != nil)
    }

    @Test
    func `fails clearly when id is missing`() {
        #expect(throws: DecodingError.self) {
            try decode(#"{"title": "no id"}"#)
        }
    }
}

@Suite("Open Pad by ID validation")
struct PadIDValidationTests {
    @Test
    func `accepts plain alphanumeric ids`() {
        #expect(PadIDValidation.normalize(" ABC123xy ") == "ABC123xy")
    }

    @Test
    func `rejects input that would rewrite the opened URL (#778)`() {
        let bad = ["abcd?next", "abcd#frag", "foo/bar", "a b", "", "   ",
                   "p\u{00E1}d", String(repeating: "a", count: 65)]
        for value in bad {
            #expect(PadIDValidation.normalize(value) == nil, "\(value) should be rejected")
        }
    }
}

@Suite("Model conveniences")
struct ModelConveniencesTests {
    private func pad(_ json: String) throws -> Pad {
        try CoderPadClient.decoder.decode(Pad.self, from: Data(json.utf8))
    }

    private func question(_ json: String) throws -> Question {
        try CoderPadClient.decoder.decode(Question.self, from: Data(json.utf8))
    }

    @Test
    func `pad webURL and playbackURL parse the API strings`() throws {
        let decoded = try pad(#"""
        {"id": "P1", "url": "https://app.coderpad.io/P1", "playback": "https://app.coderpad.io/P1/playback"}
        """#)
        #expect(decoded.webURL == URL(string: "https://app.coderpad.io/P1"))
        #expect(decoded.playbackURL == URL(string: "https://app.coderpad.io/P1/playback"))

        // No playback string → no playback URL.
        #expect(try pad(#"{"id": "P2", "url": "https://app.coderpad.io/P2"}"#).playbackURL == nil)
    }

    @Test
    func `question webURL is built from the account's base URL`() throws {
        let decoded = try question(#"{"id": 42, "title": "Two Sum"}"#)
        #expect(try decoded.webURL(baseURL: #require(URL(string: "https://app.coderpad.io")))
            == URL(string: "https://app.coderpad.io/questions/42"))
        // Honors a custom CoderPad domain.
        #expect(try decoded.webURL(baseURL: #require(URL(string: "https://acme.coderpad.io")))
            == URL(string: "https://acme.coderpad.io/questions/42"))
    }

    @Test
    func `pad isEnded prefers ended_at then falls back to state`() throws {
        #expect(try pad(#"{"id": "P", "state": "started"}"#).isEnded == false)
        #expect(try pad(#"{"id": "P", "state": "ended"}"#).isEnded == true)
        // ended_at present overrides a non-terminal state.
        #expect(try pad(#"{"id": "P", "state": "started", "ended_at": "2026-06-09T23:02:35Z"}"#).isEnded == true)
    }

    @Test
    func `interviewType normalizes the spellings the API has used`() {
        #expect(InterviewType(rawType: "live") == .live)
        #expect(InterviewType(rawType: "take-home") == .takeHome)
        #expect(InterviewType(rawType: "take_home") == .takeHome)
        #expect(InterviewType(rawType: "takehome") == .takeHome)
        #expect(InterviewType(rawType: "TAKE-HOME") == .takeHome)
        #expect(InterviewType(rawType: nil) == nil)
        #expect(InterviewType(rawType: "mystery") == nil)
    }

    @Test
    func `question interviewType prefers pad_type then take_home, defaulting to live`() throws {
        #expect(try question(#"{"id": 1, "pad_type": "take-home", "take_home": false}"#).interviewType == .takeHome)
        #expect(try question(#"{"id": 2, "take_home": true}"#).interviewType == .takeHome)
        #expect(try question(#"{"id": 3}"#).interviewType == .live)
    }

    @Test
    func `padState folds synonyms and preserves unknown values`() {
        #expect(PadState(apiState: "started") == .active)
        #expect(PadState(apiState: "running") == .active)
        #expect(PadState(apiState: "finished") == .ended)
        #expect(PadState(apiState: "draft") == .pending)
        #expect(PadState(apiState: "queued") == .other("queued"))
        // Round-trips through its rawValue (backs saved-search persistence).
        #expect(PadState(rawValue: "ended") == .ended)
        #expect(PadState.other("queued").rawValue == "queued")
    }
}

@Suite("CodeFile language and name")
struct CodeFileTests {
    @Test
    func `maps known extensions to highlighter languages`() {
        #expect(CodeFile.language(forPath: "main.py", fallback: nil) == "python")
        #expect(CodeFile.language(forPath: "app.tsx", fallback: nil) == "typescript")
        #expect(CodeFile.language(forPath: "src/lib/Foo.swift", fallback: nil) == "swift")
        // Extension match is case-insensitive.
        #expect(CodeFile.language(forPath: "Main.PY", fallback: nil) == "python")
    }

    @Test
    func `falls back to the environment language, stripping the multifile prefix`() {
        // No usable extension → use the fallback, with `multifile_` stripped.
        #expect(CodeFile.language(forPath: "Makefile", fallback: "multifile_python") == "python")
        #expect(CodeFile.language(forPath: nil, fallback: "multifile_javascript") == "javascript")
        // An unknown extension also defers to the fallback.
        #expect(CodeFile.language(forPath: "data.xyz", fallback: "go") == "go")
        // A trailing dot has no real extension, so it falls back too.
        #expect(CodeFile.language(forPath: "file.", fallback: nil) == nil)
    }

    @Test
    func `name is the last path component, or untitled when absent`() {
        #expect(CodeFile(id: "1", path: "src/main.rs", contents: "", language: nil).name == "main.rs")
        #expect(CodeFile(id: "2", path: nil, contents: "", language: nil).name == "untitled")
        #expect(CodeFile(id: "3", path: "", contents: "", language: nil).name == "untitled")
    }
}

@Suite("Account validation messages")
@MainActor
struct AccountValidationMessageTests {
    private func editor() -> AccountEditor {
        AccountEditor(
            initial: Account(name: "", apiKey: "test-key"),
            onSave: { _ in },
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
        #expect(message.contains("couldn't validate this key"))
    }
}
