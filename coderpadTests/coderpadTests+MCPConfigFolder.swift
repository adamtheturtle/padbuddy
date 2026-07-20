//
//  coderpadTests+MCPConfigFolder.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

#if os(macOS)
    @Suite("MCP config folder resolution")
    struct MCPConfigFolderTests {
        @Test
        func `parent grant creates and resolves the exact missing client folder`() throws {
            let parent = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcp-config-parent-\(UUID().uuidString)", isDirectory: true)
            let preferred = parent.appendingPathComponent(".codex", isDirectory: true)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: parent) }

            let resolved = try MCPClientInstall.configurationFolder(
                granted: parent, preferred: preferred, fallback: parent
            )

            #expect(resolved == preferred)
            #expect(FileManager.default.fileExists(atPath: preferred.path))
            #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("config.toml").path))
        }

        @Test
        func `an explicitly selected folder is never redirected`() throws {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("mcp-config-choice-\(UUID().uuidString)", isDirectory: true)
            let fallback = root.appendingPathComponent("parent", isDirectory: true)
            let preferred = fallback.appendingPathComponent(".cursor", isDirectory: true)
            let chosen = root.appendingPathComponent("chosen", isDirectory: true)
            try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let resolved = try MCPClientInstall.configurationFolder(
                granted: chosen, preferred: preferred, fallback: fallback
            )

            #expect(resolved == chosen)
            #expect(!FileManager.default.fileExists(atPath: preferred.path))
        }
    }
#endif
