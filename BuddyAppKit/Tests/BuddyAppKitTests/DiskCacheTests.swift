//
//  DiskCacheTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Foundation
import os
import Testing

@Suite("Disk cache paths")
struct DiskCacheTests {
    @Test(arguments: ["pads", "questions_v2", "organization-cache", "A1"])
    func `safe filename tokens are accepted`(kind: String) {
        #expect(DiskCache.isValidKind(kind))
    }

    @Test(arguments: ["", ".", "..", "../pads", "nested/pads", #"nested\pads"#, "pads.json", "💾"])
    func `path-like and non-ASCII kinds are rejected`(kind: String) {
        #expect(!DiskCache.isValidKind(kind))
    }

    @Test
    func `unreasonably long kinds are rejected`() {
        #expect(!DiskCache.isValidKind(String(repeating: "a", count: 65)))
    }

    @Test
    func `saved snapshots and their directory are private to the user`() throws {
        let suffix = UUID().uuidString
        let directoryName = "com.buddyappkit.tests.DiskCache-\(suffix)"
        let account = UUID()
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }

        cache.save(["secret"], kind: "pads", account: account)

        let file = directory.appending(path: "pads-\(account.uuidString).json")
        let directoryMode = try #require(
            FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        )
        let fileMode = try #require(
            FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        )
        #expect(directoryMode & 0o777 == 0o700)
        #expect(fileMode & 0o777 == 0o600)
    }

    @Test
    func `a corrupt snapshot is reported once and removed`() throws {
        let directoryName = "com.buddyappkit.tests.DiskCache-\(UUID().uuidString)"
        let account = UUID()
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        let file = directory.appending(path: "pads-\(account.uuidString).json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)

        guard case .corrupt = cache.loadResult([String].self, kind: "pads", account: account) else {
            Issue.record("Expected a recoverable corruption result")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: file.path))
        guard case .missing = cache.loadResult([String].self, kind: "pads", account: account) else {
            Issue.record("Expected the removed snapshot to become a cache miss")
            return
        }
    }
}
