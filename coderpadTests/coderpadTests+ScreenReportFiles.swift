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

@Suite("Screen report temp files", .serialized)
struct ScreenReportFilesTests {
    private var pdf: Data {
        ScreenTestFixtures.reportPDF(candidate: "Test Candidate", score: 75)
    }

    @Test
    func `PDF validation rejects a spoofed magic prefix`() {
        #expect(ScreenReportFiles.isLikelyPDF(pdf))
        #expect(!ScreenReportFiles.isLikelyPDF(Data("%PDF-1.7\nnot a document".utf8)))
    }

    @Test
    func `staging the same test ID twice yields distinct files`() throws {
        let first = try ScreenReportFiles.stage(pdf, testID: 42)
        let second = try ScreenReportFiles.stage(pdf, testID: 42)
        defer {
            ScreenReportFiles.remove(first)
            ScreenReportFiles.remove(second)
        }

        #expect(first != second)
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent())
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
    func `launch cleanup preserves reports staged by this process`() throws {
        let first = try ScreenReportFiles.stage(pdf, testID: 1)
        let second = try ScreenReportFiles.stage(pdf, testID: 2)
        defer {
            ScreenReportFiles.remove(first)
            ScreenReportFiles.remove(second)
        }
        ScreenReportFiles.cleanUpLeftovers()
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test
    func `staging rejects nonpositive test IDs`() {
        #expect(throws: CocoaError.self) { try ScreenReportFiles.stage(pdf, testID: 0) }
        #expect(throws: CocoaError.self) { try ScreenReportFiles.stage(pdf, testID: -1) }
    }

    @Test
    func `a rejected viewer launch removes the staged report immediately`() throws {
        let url = try ScreenReportFiles.stage(pdf, testID: 10)

        ScreenReportFiles.handleOpenResult(false, for: url)

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path))
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
