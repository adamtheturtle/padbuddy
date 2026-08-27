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
#endif
