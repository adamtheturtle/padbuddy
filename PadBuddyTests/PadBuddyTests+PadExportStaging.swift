//
//  PadBuddyTests+PadExportStaging.swift
//  PadBuddyTests
//

import Foundation
@testable import PadBuddy
import Testing

@Suite("Pad export staging cleanup")
struct PadExportStagingTests {
    @Test func `sweep removes only padbuddy export zip archives (#4665)`() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PadExportStagingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keep = root.appendingPathComponent("notes.txt")
        let remove = root.appendingPathComponent("padbuddy-export-\(UUID().uuidString).zip")
        let otherZip = root.appendingPathComponent("other.zip")
        try Data("keep".utf8).write(to: keep)
        try Data("secret".utf8).write(to: remove)
        try Data("other".utf8).write(to: otherZip)

        #expect(sweepPadbuddyExportArchives(in: root) == 1)
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(FileManager.default.fileExists(atPath: otherZip.path))
        #expect(!FileManager.default.fileExists(atPath: remove.path))
    }
}
