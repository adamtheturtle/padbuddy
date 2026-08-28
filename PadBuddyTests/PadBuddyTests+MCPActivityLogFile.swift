//
//  PadBuddyTests+MCPActivityLogFile.swift
//  PadBuddyTests
//

#if os(macOS)
    import Darwin
    import Foundation
    @testable import PadBuddy
    import Testing

    @Suite("MCP activity log file handling (#4718, #4719)")
    struct MCPActivityLogFileTests {
        private func directory() throws -> URL {
            let url = URL.temporaryDirectory.appending(
                path: "mcp-log-\(UUID().uuidString)", directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func mode(of url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return try #require(attributes[.posixPermissions] as? Int)
        }

        @Test func `a rewritten log is created user-private`() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appending(path: "mcp-activity.jsonl")

            try MCPActivityLog.writeRestrictedLog(Data("first\n".utf8), to: url)

            // `Data.write(to:options:.atomic)` took the new inode's mode from the umask,
            // so the log spent most of its life group- and world-readable.
            #expect(try mode(of: url) == 0o600)
            #expect(try Data(contentsOf: url) == Data("first\n".utf8))
        }

        @Test func `replacing an existing log keeps it user-private`() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appending(path: "mcp-activity.jsonl")
            try Data("old\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

            try MCPActivityLog.writeRestrictedLog(Data("new\n".utf8), to: url)

            #expect(try mode(of: url) == 0o600)
            #expect(try Data(contentsOf: url) == Data("new\n".utf8))
        }

        @Test func `a symlink at the log path is replaced rather than followed`() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let target = root.appending(path: "victim.txt")
            try Data("do not touch\n".utf8).write(to: target)
            let url = root.appending(path: "mcp-activity.jsonl")
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)

            try MCPActivityLog.writeRestrictedLog(Data("new\n".utf8), to: url)

            // The link is gone, replaced by the real log; whatever it pointed at is intact.
            #expect(try Data(contentsOf: target) == Data("do not touch\n".utf8))
            #expect(try Data(contentsOf: url) == Data("new\n".utf8))
            #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil)
        }

        @Test func `no temporary file is left behind`() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }

            try MCPActivityLog.writeRestrictedLog(Data("x\n".utf8), to: root.appending(path: "mcp-activity.jsonl"))

            let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
            #expect(contents == ["mcp-activity.jsonl"])
        }

        @Test func `an empty payload still produces a private file`() throws {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appending(path: "mcp-activity.jsonl")

            try MCPActivityLog.writeRestrictedLog(Data(), to: url)

            #expect(try mode(of: url) == 0o600)
        }
    }
#endif
