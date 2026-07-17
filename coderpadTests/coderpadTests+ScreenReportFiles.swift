//
//  coderpadTests+ScreenReportFiles.swift
//  coderpadTests
//
//  Staging and cleanup of opened Screen report PDFs (#804, #807): unique per-invocation
//  paths so equal test IDs never collide across accounts, and removal that leaves no
//  candidate data behind.
//

@testable import CoderPad
import Foundation
import Testing

@Suite("Screen report temp files")
struct ScreenReportFilesTests {
    @Test
    func `staging the same test ID twice yields distinct files`() throws {
        let first = try ScreenReportFiles.stage(Data("a".utf8), testID: 42)
        let second = try ScreenReportFiles.stage(Data("b".utf8), testID: 42)
        defer {
            ScreenReportFiles.remove(first)
            ScreenReportFiles.remove(second)
        }

        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("a".utf8))
        #expect(try Data(contentsOf: second) == Data("b".utf8))
        #expect(first.lastPathComponent == "ScreenReport-42.pdf")
    }

    @Test
    func `staged folder is owner only`() throws {
        let url = try ScreenReportFiles.stage(Data("x".utf8), testID: 7)
        defer { ScreenReportFiles.remove(url) }

        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.deletingLastPathComponent().path
        )
        let permissions = attributes[.posixPermissions] as? Int
        #expect(permissions == 0o700)
    }

    @Test
    func `remove deletes the report and its folder`() throws {
        let url = try ScreenReportFiles.stage(Data("x".utf8), testID: 9)
        ScreenReportFiles.remove(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test
    func `launch cleanup sweeps every staged report`() throws {
        let first = try ScreenReportFiles.stage(Data("a".utf8), testID: 1)
        let second = try ScreenReportFiles.stage(Data("b".utf8), testID: 2)
        ScreenReportFiles.cleanUpLeftovers()
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }
}
