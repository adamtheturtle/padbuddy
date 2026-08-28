//
//  PadBuddyTests+DurableExport.swift
//  PadBuddyTests
//

#if os(macOS)
    import Foundation
    @testable import PadBuddy
    import Testing

    @Suite("Durable export")
    struct DurableExportTests {
        @Test
        func `durable export synchronizes a nested tree and its parent`() throws {
            let parent = FileManager.default.temporaryDirectory
                .appending(path: "durable-export-\(UUID().uuidString)", directoryHint: .isDirectory)
            let nested = parent.appending(path: "project/src", directoryHint: .isDirectory)
            let file = nested.appending(path: "main.swift")
            defer { try? FileManager.default.removeItem(at: parent) }
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try Data("print(42)".utf8).write(to: file)

            try DurableExport.synchronizeTree(at: parent)
            try DurableExport.synchronizeDirectory(at: parent.deletingLastPathComponent())

            #expect(try Data(contentsOf: file) == Data("print(42)".utf8))
        }

        @Test
        func `durable export reports a missing file`() {
            let missing = FileManager.default.temporaryDirectory
                .appending(path: "missing-\(UUID().uuidString)")

            #expect(throws: (any Error).self) {
                try DurableExport.synchronizeFile(at: missing)
            }
        }
    }

    @Suite("Durable export failure reporting (#4611, #4612)")
    struct DurableExportFailureTests {
        private func makeTree() throws -> URL {
            let root = URL.temporaryDirectory.appending(
                path: "durable-\(UUID().uuidString)", directoryHint: .isDirectory
            )
            let nested = root.appending(path: "nested", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try "a".write(to: root.appending(path: "a.txt"), atomically: true, encoding: .utf8)
            try "b".write(to: nested.appending(path: "b.txt"), atomically: true, encoding: .utf8)
            return root
        }

        @Test func `a readable tree synchronizes`() throws {
            let root = try makeTree()
            defer { try? FileManager.default.removeItem(at: root) }

            try DurableExport.synchronizeTree(at: root)
        }

        @Test func `an unreadable subtree fails rather than reporting success`() throws {
            let root = try makeTree()
            let nested = root.appending(path: "nested", directoryHint: .isDirectory)
            defer {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nested.path)
                try? FileManager.default.removeItem(at: root)
            }
            // Enumeration used to skip a subtree it could not read and carry on, so the
            // export was declared durable having never touched those files.
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: nested.path)

            #expect(throws: (any Error).self) {
                try DurableExport.synchronizeTree(at: root)
            }
        }

        @Test func `a missing file is reported`() {
            let missing = URL.temporaryDirectory.appending(path: "absent-\(UUID().uuidString)")

            #expect(throws: (any Error).self) {
                try DurableExport.synchronizeFile(at: missing)
            }
        }
    }
#endif
