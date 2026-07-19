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
    private let pdf = Data("%PDF-1.7\nbody".utf8)

    @Test
    func `staging the same test ID twice yields distinct files`() throws {
        let first = try ScreenReportFiles.stage(pdf, testID: 42)
        let second = try ScreenReportFiles.stage(pdf, testID: 42)
        defer {
            ScreenReportFiles.remove(first)
            ScreenReportFiles.remove(second)
        }

        #expect(first != second)
        #expect(try Data(contentsOf: first) == pdf)
        #expect(try Data(contentsOf: second) == pdf)
        #expect(first.lastPathComponent == "ScreenReport-42.pdf")
    }

    @Test
    func `staged folder is owner only`() throws {
        let url = try ScreenReportFiles.stage(pdf, testID: 7)
        defer { ScreenReportFiles.remove(url) }

        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.deletingLastPathComponent().path
        )
        let permissions = attributes[.posixPermissions] as? Int
        #expect(permissions == 0o700)
    }

    @Test
    func `remove deletes the report and its folder`() throws {
        let url = try ScreenReportFiles.stage(pdf, testID: 9)
        ScreenReportFiles.remove(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
    }

    @Test
    func `launch cleanup sweeps every staged report`() throws {
        let first = try ScreenReportFiles.stage(pdf, testID: 1)
        let second = try ScreenReportFiles.stage(pdf, testID: 2)
        ScreenReportFiles.cleanUpLeftovers()
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
    }

    @Test
    func `staging rejects nonpositive test IDs`() {
        #expect(throws: CocoaError.self) { try ScreenReportFiles.stage(pdf, testID: 0) }
        #expect(throws: CocoaError.self) { try ScreenReportFiles.stage(pdf, testID: -1) }
    }

    @Test
    func `report size limit includes its boundary and rejects larger counts`() {
        #expect(ScreenReportFiles.isWithinSizeLimit(ScreenReportFiles.maxReportBytes))
        #expect(!ScreenReportFiles.isWithinSizeLimit(ScreenReportFiles.maxReportBytes + 1))
        #expect(!ScreenReportFiles.isWithinSizeLimit(-1))
    }

    @Test
    func `network report limit checks declared and downloaded sizes`() {
        let maximum = ScreenReportFiles.maxReportBytes
        #expect(ScreenClient.isAllowedReportSize(declared: -1, actual: maximum))
        #expect(ScreenClient.isAllowedReportSize(declared: Int64(maximum), actual: maximum))
        #expect(!ScreenClient.isAllowedReportSize(declared: Int64(maximum + 1), actual: 1))
        #expect(!ScreenClient.isAllowedReportSize(declared: -1, actual: maximum + 1))
        #expect(!ScreenClient.isAllowedReportSize(declared: -1, actual: -1))
    }
}
