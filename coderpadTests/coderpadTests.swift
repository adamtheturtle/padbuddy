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
    func `accepts hyphens and underscores (#2694)`() {
        // A self-hosted server can issue slugs containing these, and neither can
        // change the structure of the URL the id is interpolated into.
        #expect(PadIDValidation.normalize("my-pad_01") == "my-pad_01")
        #expect(PadIDValidation.normalize("-_-") == "-_-")
    }

    @Test
    func `rejects input that would rewrite the opened URL (#778)`() {
        let bad = ["abcd?next", "abcd#frag", "foo/bar", "a b", "", "   ",
                   "p\u{00E1}d", String(repeating: "a", count: 65),
                   // Still rejected after #2694 widened the set: each of these can
                   // change the path, query, fragment, authority, or extension of the
                   // URL the id lands in.
                   "a:b", "a@b", "a.b", "../etc", "a%2Fb", "a&b", "a=b"]
        for value in bad {
            #expect(PadIDValidation.normalize(value) == nil, "\(value) should be rejected")
        }
    }

    @Test
    func `accepts the maximum length and rejects one more`() {
        #expect(PadIDValidation.normalize(String(repeating: "a", count: 64)) != nil)
        #expect(PadIDValidation.normalize(String(repeating: "a", count: 65)) == nil)
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
    func `pad webURL falls back to the account base`() throws {
        let missing = try pad(#"{"id": "P2"}"#)
        let malformed = try pad(#"{"id": "P3", "url": "://not-a-url"}"#)
        let base = try #require(URL(string: "https://custom.example.com/pads"))

        #expect(missing.webURL(fallbackBase: base) == URL(string: "https://custom.example.com/pads/P2"))
        #expect(malformed.webURL(fallbackBase: base) == URL(string: "https://custom.example.com/pads/P3"))
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
    func `maps common project-file languages`() {
        #expect(CodeFile.language(forPath: "package.json", fallback: nil) == "json")
        #expect(CodeFile.language(forPath: "compose.yaml", fallback: nil) == "yaml")
        #expect(CodeFile.language(forPath: "config.yml", fallback: nil) == "yaml")
        #expect(CodeFile.language(forPath: "pyproject.toml", fallback: nil) == "toml")
        #expect(CodeFile.language(forPath: "App.vue", fallback: nil) == "xml")
        #expect(CodeFile.language(forPath: "App.svelte", fallback: nil) == "xml")
        #expect(CodeFile.language(forPath: "build.gradle", fallback: nil) == "groovy")
        #expect(CodeFile.language(forPath: "deploy/DOCKERFILE", fallback: nil) == "dockerfile")
    }

    @Test
    func `uses the environment to disambiguate m files`() {
        #expect(CodeFile.language(forPath: "main.m", fallback: "matlab") == "matlab")
        #expect(CodeFile.language(forPath: "main.m", fallback: "multifile_matlab") == "matlab")
        #expect(CodeFile.language(forPath: "main.m", fallback: "objective-c") == "objective-c")
        #expect(CodeFile.language(forPath: "main.m", fallback: nil) == "objective-c")
    }

    @Test
    func `uses the environment to disambiguate h files`() {
        #expect(CodeFile.language(forPath: "library.h", fallback: "cpp") == "cpp")
        #expect(CodeFile.language(forPath: "library.h", fallback: "multifile_cpp") == "cpp")
        #expect(CodeFile.language(forPath: "library.h", fallback: "c") == "c")
        #expect(CodeFile.language(forPath: "library.h", fallback: nil) == "c")
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

@Suite("Code card file selection")
@MainActor
struct EnvironmentCodeCardSelectionTests {
    private func makeCard(files: [CodeFile]) -> EnvironmentCodeCard {
        EnvironmentCodeCard(
            files: files,
            isActive: false,
            showActiveBadge: false,
            language: "python",
            padID: "pad",
            dark: false
        )
    }

    /// The id index built in `init` has to answer exactly what the old linear
    /// scan did, including both fallbacks (#2103).
    @Test
    func `selection resolves by id and falls back to the first file`() {
        let card = makeCard(files: [
            CodeFile(id: "a", path: "a.py", contents: "a", language: "python"),
            CodeFile(id: "b", path: "dir/b.py", contents: "b", language: "python")
        ])

        // Nothing selected yet: the first file shows.
        #expect(card.selected.id == "a")
        card.selectedFileID = "b"
        #expect(card.selected.id == "b")
        // A selection that no longer names a present file falls back too.
        card.selectedFileID = "gone"
        #expect(card.selected.id == "a")
        // With no files at all, the placeholder keeps `selected` total.
        #expect(makeCard(files: []).selected.id == CodeFile.placeholder.id)
    }
}

@Suite("Code card file tree")
struct EnvironmentCodeCardFileTreeTests {
    @Test
    func `machine paths use deterministic lexical ordering`() {
        let tree = EnvironmentCodeCard.makeFileTree(from: [
            CodeFile(id: "lower-folder", path: "alpha/main.swift", contents: "", language: nil),
            CodeFile(id: "upper-folder", path: "Beta/main.swift", contents: "", language: nil),
            CodeFile(id: "lower-file", path: "alpha.swift", contents: "", language: nil),
            CodeFile(id: "upper-file", path: "Beta.swift", contents: "", language: nil)
        ])

        #expect(tree.map(\.name) == ["Beta", "alpha", "Beta.swift", "alpha.swift"])
    }
}
