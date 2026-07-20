//
//  coderpadTests+MCPPadCode.swift
//  coderpadTests
//
//  Tests for the in-app MCP server's get_pad_code assembly (#499): multi-file
//  precedence, the legacy single-file fallback, filename synthesis, and truncation.
//  The assembly is pure, so it's tested without network.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("MCP get_pad_code assembly")
struct MCPPadCodeTests {
    @Test
    func `environment loading uses a bounded width`() {
        #expect(MCPTools.maxPadEnvironmentConcurrency == 4)
    }

    @Test
    func `synthesized filenames map known languages and fall back`() {
        #expect(synthesizedFilename(language: "python") == "main.py")
        #expect(synthesizedFilename(language: "C++") == "main.cpp")
        #expect(synthesizedFilename(language: "ocaml") == "main.ocaml")
        #expect(synthesizedFilename(language: nil) == "main.txt")
        #expect(synthesizedFilename(language: "") == "main.txt")
    }

    @Test
    func `truncate appends a marker only when over the limit`() {
        #expect(truncate("hello", to: nil) == "hello")
        #expect(truncate("hello", to: 10) == "hello")
        let cut = truncate("hello", to: 3)
        #expect(cut.hasPrefix("hel"))
        #expect(cut.contains("2 more bytes"))
    }

    @Test
    func `max file char validation rejects non-positive explicit limits`() {
        #expect(maxFileCharsValidationError(nil) == nil)
        #expect(maxFileCharsValidationError(1) == nil)
        #expect(maxFileCharsValidationError(0) != nil)
        #expect(maxFileCharsValidationError(-1) != nil)
    }

    @Test
    func `environment ids coerce int and string forms and drop duplicates`() {
        #expect(environmentIDs(in: ["pad_environment_ids": [1, "2", 3, "2", 1]]) == [1, 2, 3])
        #expect(environmentIDs(in: [:]).isEmpty)
    }

    @Test
    func `multi-file environments win and carry filenames, language, and id`() {
        let pad: [String: Any] = ["title": "Interview", "contents": "legacy", "language": "python"]
        let env = CoderPadToolCore.PadCodeEnvironment(id: 9, object: [
            "language": "javascript",
            "file_contents": [
                ["path": "index.js", "contents": "console.log(1)"],
                ["contents": "no path"]
            ]
        ])
        let files = padCodeFiles(pad: pad, environments: [env], maxFileChars: nil)
        #expect(files.count == 2)
        #expect(files[0]["filename"] as? String == "index.js")
        #expect(files[0]["language"] as? String == "javascript")
        #expect(files[0]["environment_id"] as? Int == 9)
        #expect(files[1]["filename"] as? String == "main.js")
        #expect(!files.contains { ($0["contents"] as? String) == "legacy" })
    }

    @Test
    func `legacy single-file pad is the fallback when no environment files exist`() {
        let pad: [String: Any] = ["title": "Legacy", "contents": "print('hi')", "language": "python"]
        let files = padCodeFiles(pad: pad, environments: [], maxFileChars: nil)
        #expect(files.count == 1)
        #expect(files[0]["filename"] as? String == "main.py")
        #expect(files[0]["contents"] as? String == "print('hi')")
    }

    @Test
    func `binary files are explicit and do not fabricate text contents`() {
        let env = CoderPadToolCore.PadCodeEnvironment(id: 9, object: [
            "file_contents": [["path": "logo.png", "contents": NSNull(), "binary": true]]
        ])
        let file = padCodeFiles(pad: [:], environments: [env], maxFileChars: nil)[0]
        #expect(file["filename"] as? String == "logo.png")
        #expect(file["binary"] as? Bool == true)
        #expect(file["contents"] == nil)
    }

    @Test
    func `legacy contents are not substituted when every declared environment is missing`() {
        let pad: [String: Any] = [
            "title": "Multi-file",
            "contents": "stale legacy code",
            "pad_environment_ids": [1, 2]
        ]

        let files = padCodeFiles(pad: pad, environments: [], maxFileChars: nil)
        let payload = padCodePayload(id: "abc", pad: pad, environments: [], maxFileChars: nil)

        #expect(files.isEmpty)
        #expect((payload["files"] as? [[String: Any]])?.isEmpty == true)
        #expect(payload["incomplete"] as? Bool == true)
        #expect(payload["missing_environment_ids"] as? [Int] == [1, 2])
    }

    @Test
    func `total declared environment failure is an MCP error`() {
        #expect(MCPTools.padCodeFetchIsError(referencedEnvironmentIDs: [1, 2], fetchedEnvironmentCount: 0))
        #expect(!MCPTools.padCodeFetchIsError(referencedEnvironmentIDs: [1, 2], fetchedEnvironmentCount: 1))
        #expect(!MCPTools.padCodeFetchIsError(referencedEnvironmentIDs: [], fetchedEnvironmentCount: 0))
    }

    @Test
    func `payload wraps id, title, and files; truncation applies per file`() {
        let pad: [String: Any] = ["title": "T", "contents": "0123456789", "language": "python"]
        let payload = padCodePayload(id: "abc", pad: pad, environments: [], maxFileChars: 4)
        #expect(payload["pad_id"] as? String == "abc")
        #expect(payload["title"] as? String == "T")
        let files = payload["files"] as? [[String: Any]] ?? []
        #expect(files.count == 1)
        #expect((files[0]["contents"] as? String)?.contains("6 more bytes") == true)
    }

    @Test
    func `payload marks failed environment fetches as incomplete`() {
        let pad: [String: Any] = ["title": "T", "pad_environment_ids": [1, 2]]
        let env = CoderPadToolCore.PadCodeEnvironment(id: 1, object: [
            "file_contents": [["path": "a.py", "contents": "print(1)"]]
        ])
        let payload = padCodePayload(
            id: "abc", pad: pad, environments: [env], maxFileChars: nil, failedEnvironmentIDs: [2]
        )
        #expect(payload["incomplete"] as? Bool == true)
        #expect(payload["missing_environment_ids"] as? [Int] == [2])

        // Completeness is derived from the pad's referenced environments (#1598):
        // environment 2 was never fetched, so this stays incomplete even with no
        // failed ids reported.
        let derived = padCodePayload(id: "abc", pad: pad, environments: [env], maxFileChars: nil)
        #expect(derived["incomplete"] as? Bool == true)

        let both = [env, CoderPadToolCore.PadCodeEnvironment(id: 2, object: [:])]
        let complete = padCodePayload(id: "abc", pad: pad, environments: both, maxFileChars: nil)
        #expect(complete["incomplete"] == nil)
    }
}
