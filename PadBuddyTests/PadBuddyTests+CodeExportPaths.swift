//
//  PadBuddyTests+CodeExportPaths.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Code export paths")
struct CodeExportPathTests {
    @Test
    func `explanation key changes when contents or language changes`() {
        let original = CodeFile(id: "1", path: "main.swift", contents: "print(1)", language: "swift")
        let changedContents = CodeFile(id: "1", path: "main.swift", contents: "print(2)", language: "swift")
        let changedLanguage = CodeFile(id: "1", path: "main.swift", contents: "print(1)", language: "python")

        #expect(original.explanationKey != changedContents.explanationKey)
        #expect(original.explanationKey != changedLanguage.explanationKey)
    }

    @Test
    func `components drop traversal segments`() {
        let file = CodeFile(id: "1", path: "../src/./main.swift", contents: "", language: nil)

        #expect(CodeExportPathPlan.components(for: file) == ["src", "main.swift"])
    }

    @Test
    func `sanitized export root rejects dot only names`() {
        #expect(PadDetailView.sanitizeComponent(".") == "untitled")
        #expect(PadDetailView.sanitizeComponent("..") == "untitled")
        #expect(PadDetailView.sanitizeComponent(" ... ") == "untitled")
    }

    @Test
    func `sanitized components stay within the filesystem byte limit (#4667)`() {
        let longStem = String(repeating: "a", count: 300)
        let sanitized = PadDetailView.sanitizeComponent("\(longStem).swift")

        #expect(sanitized.utf8.count <= SaveCodePathHelpers.maximumComponentUTF8Bytes)
        #expect(sanitized.hasSuffix(".swift"))

        let emoji = String(repeating: "🦺", count: 80)
        let emojiSanitized = PadDetailView.sanitizeComponent(emoji)
        #expect(emojiSanitized.utf8.count <= SaveCodePathHelpers.maximumComponentUTF8Bytes)
        #expect(!emojiSanitized.isEmpty)
    }

    @Test
    func `collision suffixes keep unique paths within the byte limit (#4667)`() {
        let longName = String(repeating: "b", count: 250) + ".txt"
        let paths = PadDetailView.uniqueRelativePaths([longName, longName, longName])

        #expect(Set(paths).count == 3)
        #expect(paths.allSatisfy { $0.utf8.count <= SaveCodePathHelpers.maximumComponentUTF8Bytes })
        #expect(paths.allSatisfy { $0.hasSuffix(".txt") })
    }

    @Test
    func `unique relative paths preserve sanitized filename collisions`() {
        let paths = PadDetailView.uniqueRelativePaths([
            "src/foo-.js",
            "src/foo-.js",
            "src/foo-2.js",
            "src/foo-.js"
        ])

        #expect(paths == [
            "src/foo-.js",
            "src/foo--2.js",
            "src/foo-2.js",
            "src/foo--3.js"
        ])
    }

    @Test
    func `unique relative paths rename case-only collisions (#1040)`() {
        // Case-insensitive volumes (APFS default) treat README.md and readme.md as
        // one file, so the second must be renamed, keeping its own casing.
        let paths = PadDetailView.uniqueRelativePaths([
            "README.md",
            "readme.md",
            "src/Main.java",
            "src/main.java"
        ])

        #expect(paths == [
            "README.md",
            "readme-2.md",
            "src/Main.java",
            "src/main-2.java"
        ])
    }

    @Test
    func `folder download path plan renames exact and case-only collisions (#1040)`() {
        let files = [
            CodeFile(id: "1", path: "README.md", contents: "a", language: nil),
            CodeFile(id: "2", path: "readme.md", contents: "b", language: nil),
            CodeFile(id: "3", path: "readme.md", contents: "c", language: nil)
        ]

        #expect(CodeExportPathPlan.uniqueRelativePaths(for: files) == [
            "README.md",
            "readme-2.md",
            "readme-3.md"
        ])
    }

    @Test
    func `path plan rejects file directory collisions`() throws {
        let files = [
            CodeFile(id: "1", path: "src", contents: "", language: nil),
            CodeFile(id: "2", path: "src/main.swift", contents: "", language: nil)
        ]

        #expect(throws: CodeExportPathError.self) {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
        }
    }

    @Test
    func `path plan rejects case-insensitive file directory collisions`() throws {
        let files = [
            CodeFile(id: "1", path: "foo", contents: "", language: nil),
            CodeFile(id: "2", path: "FOO/bar.swift", contents: "", language: nil)
        ]

        #expect(throws: CodeExportPathError.self) {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
        }
    }

    @Test
    func `path plan rejects canonically equivalent file directory collisions`() throws {
        let files = [
            CodeFile(id: "1", path: "café", contents: "", language: nil),
            CodeFile(id: "2", path: "cafe\u{301}/menu.txt", contents: "", language: nil)
        ]

        #expect(throws: CodeExportPathError.self) {
            try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
        }
    }

    @Test
    func `path plan allows duplicate leaf files for later renaming`() throws {
        let files = [
            CodeFile(id: "1", path: "src/main.swift", contents: "", language: nil),
            CodeFile(id: "2", path: "src/main.swift", contents: "", language: nil)
        ]

        try CodeExportPathPlan.validateNoFileDirectoryConflicts(files)
    }

    /// The cheap emptiness check must agree with building the files (#2095), or the
    /// Save All Code command would enable and disable at the wrong times.
    @Test
    func `displayable-file check agrees with building the display files`() throws {
        func environment(_ files: [[String: Any]]) throws -> PadEnvironment {
            let data = try JSONSerialization.data(withJSONObject: ["id": 1, "file_contents": files])
            return try CoderPadClient.decoder.decode(PadEnvironment.self, from: data)
        }

        let empty = try environment([])
        // Files present, but none carrying contents: nothing to save.
        let blank = try environment([["path": "main.py", "contents": ""], ["path": "empty.py"]])
        let coded = try environment([["path": "main.py", "contents": ""],
                                     ["path": "util.py", "contents": "x = 1"]])

        #expect(!PadDetailView.hasDisplayableFiles(in: empty))
        #expect(!PadDetailView.hasDisplayableFiles(in: blank))
        #expect(PadDetailView.hasDisplayableFiles(in: coded))
    }
}
