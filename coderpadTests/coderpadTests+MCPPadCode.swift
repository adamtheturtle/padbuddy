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
    func `synthesized filenames map known languages and fall back`() {
        #expect(MCPPadCode.synthesizedFilename(language: "python") == "main.py")
        #expect(MCPPadCode.synthesizedFilename(language: "C++") == "main.cpp")
        #expect(MCPPadCode.synthesizedFilename(language: "ocaml") == "main.ocaml")
        #expect(MCPPadCode.synthesizedFilename(language: nil) == "main.txt")
        #expect(MCPPadCode.synthesizedFilename(language: "") == "main.txt")
    }

    @Test
    func `truncate appends a marker only when over the limit`() {
        #expect(MCPPadCode.truncate("hello", to: nil) == "hello")
        #expect(MCPPadCode.truncate("hello", to: 10) == "hello")
        let cut = MCPPadCode.truncate("hello", to: 3)
        #expect(cut.hasPrefix("hel"))
        #expect(cut.contains("2 more characters"))
    }

    @Test
    func `environment ids coerce int and string forms`() {
        #expect(MCPPadCode.environmentIDs(in: ["pad_environment_ids": [1, "2", 3]]) == [1, 2, 3])
        #expect(MCPPadCode.environmentIDs(in: [:]).isEmpty)
    }

    @Test
    func `multi-file environments win and carry filenames, language, and id`() {
        let pad: [String: Any] = ["title": "Interview", "contents": "legacy", "language": "python"]
        let env = MCPPadCode.Environment(id: 9, object: [
            "language": "javascript",
            "file_contents": [
                ["path": "index.js", "contents": "console.log(1)"],
                ["contents": "no path"]
            ]
        ])
        let files = MCPPadCode.files(pad: pad, environments: [env], maxFileChars: nil)
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
        let files = MCPPadCode.files(pad: pad, environments: [], maxFileChars: nil)
        #expect(files.count == 1)
        #expect(files[0]["filename"] as? String == "main.py")
        #expect(files[0]["contents"] as? String == "print('hi')")
    }

    @Test
    func `payload wraps id, title, and files; truncation applies per file`() {
        let pad: [String: Any] = ["title": "T", "contents": "0123456789", "language": "python"]
        let payload = MCPPadCode.payload(id: "abc", pad: pad, environments: [], maxFileChars: 4)
        #expect(payload["pad_id"] as? String == "abc")
        #expect(payload["title"] as? String == "T")
        let files = payload["files"] as? [[String: Any]] ?? []
        #expect(files.count == 1)
        #expect((files[0]["contents"] as? String)?.contains("6 more characters") == true)
    }
}
