//
//  DiskCacheTests.swift
//  BuddyAppKitTests
//

@testable import BuddyAppKit
import Foundation
import os
import Testing
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

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

    @Test(arguments: ["com.example.app", "com.example.app/DataCache", "Cache_2"])
    func `safe relative cache directories are accepted`(name: String) {
        #expect(DiskCache.isValidDirectoryName(name))
    }

    @Test(arguments: ["", "/tmp/cache", "../cache", "app/../cache", "app//cache", "app/", #"app\cache"#, "~"])
    func `absolute traversal and escaped cache directories are rejected`(name: String) {
        #expect(!DiskCache.isValidDirectoryName(name))
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

        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["payload"] as? [String] == ["secret"])
    }

    @Test
    func `legacy snapshots are loaded and migrated to the current envelope`() throws {
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
        try JSONEncoder().encode(["legacy"]).write(to: file)

        #expect(cache.load([String].self, kind: "pads", account: account, maximumAge: 60) == ["legacy"])

        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["payload"] as? [String] == ["legacy"])
    }

    @Test
    func `unknown schema versions are reported and removed`() throws {
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
        try Data(#"{"schemaVersion":2,"payload":["future"]}"#.utf8).write(to: file)

        guard case .corrupt = cache.loadResult(
            [String].self, kind: "pads", account: account, maximumAge: 60
        ) else {
            Issue.record("Expected an unsupported schema to be recoverable corruption")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: file.path))
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

        guard case .corrupt = cache.loadResult(
            [String].self, kind: "pads", account: account, maximumAge: 60
        ) else {
            Issue.record("Expected a recoverable corruption result")
            return
        }

        #expect(!FileManager.default.fileExists(atPath: file.path))
        guard case .missing = cache.loadResult(
            [String].self, kind: "pads", account: account, maximumAge: 60
        ) else {
            Issue.record("Expected the removed snapshot to become a cache miss")
            return
        }
    }

    @Test
    func `oversized snapshots are rejected without loading the whole file`() throws {
        let directoryName = "com.buddyappkit.tests.DiskCache-\(UUID().uuidString)"
        let account = UUID()
        let cache = DiskCache(
            directoryName: directoryName,
            logger: Logger(subsystem: "tests", category: "cache"),
            maximumSnapshotBytes: 1024
        )
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        let file = directory.appending(path: "pads-\(account.uuidString).json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 1_000_000).write(to: file)

        guard case .unavailable = cache.loadResult(
            [String].self, kind: "pads", account: account, maximumAge: 60
        ) else {
            Issue.record("Expected an oversized snapshot to be unavailable")
            return
        }

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func `FIFO snapshot is rejected without blocking`() throws {
        let fixture = try snapshotFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        #expect(mkfifo(fixture.file.path, 0o600) == 0)

        guard case .unavailable = fixture.cache.loadResult(
            [String].self, kind: "pads", account: fixture.account, maximumAge: 60
        ) else {
            Issue.record("Expected a FIFO snapshot to be unavailable")
            return
        }
    }

    @Test
    func `symbolic-link snapshot is rejected`() throws {
        let fixture = try snapshotFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let target = fixture.directory.appending(path: "target.json")
        try Data(#"{"schemaVersion":1,"payload":["secret"]}"#.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: fixture.file, withDestinationURL: target)

        guard case .unavailable = fixture.cache.loadResult(
            [String].self, kind: "pads", account: fixture.account, maximumAge: 60
        ) else {
            Issue.record("Expected a symbolic-link snapshot to be unavailable")
            return
        }
    }

    @Test
    func `atomic replacement cannot pair old bytes with the new modification date`() throws {
        let fixture = try snapshotFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.cache.save(["old"], kind: "pads", account: fixture.account)
        let oldDate = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: fixture.file.path)
        let replacement = fixture.directory.appending(path: "replacement.json")
        try Data(#"{"schemaVersion":1,"payload":["new"]}"#.utf8).write(to: replacement)
        let newDate = Date(timeIntervalSince1970: 2000)
        try FileManager.default.setAttributes([.modificationDate: newDate], ofItemAtPath: replacement.path)
        let cache = DiskCache(
            directoryName: fixture.cache.directoryName,
            logger: Logger(subsystem: "tests", category: "cache"),
            maximumSnapshotBytes: fixture.cache.maximumSnapshotBytes
        ) {
            _ = rename(replacement.path, fixture.file.path)
        }

        guard case let .value(value, modificationDate) = cache.loadResult(
            [String].self,
            kind: "pads",
            account: fixture.account,
            maximumAge: 10000,
            now: oldDate
        ) else {
            Issue.record("Expected the opened snapshot to remain readable")
            return
        }

        #expect(value == ["old"])
        #expect(modificationDate == oldDate)
        #expect(try String(contentsOf: fixture.file, encoding: .utf8).contains("new"))
    }

    @Test
    func `corruption cleanup cannot delete a concurrent fresh replacement`() throws {
        let fixture = try snapshotFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try Data("not json".utf8).write(to: fixture.file)
        let replacement = fixture.directory.appending(path: "replacement.json")
        try Data(#"{"schemaVersion":1,"payload":["fresh"]}"#.utf8).write(to: replacement)
        let cache = DiskCache(
            directoryName: fixture.cache.directoryName,
            logger: Logger(subsystem: "tests", category: "cache"),
            maximumSnapshotBytes: fixture.cache.maximumSnapshotBytes,
            afterSnapshotRead: {},
            beforeCorruptCleanup: {
                _ = rename(replacement.path, fixture.file.path)
            }
        )

        guard case .corrupt = cache.loadResult(
            [String].self, kind: "pads", account: fixture.account, maximumAge: 60
        ) else {
            Issue.record("Expected the originally opened snapshot to be corrupt")
            return
        }

        #expect(cache.load([String].self, kind: "pads", account: fixture.account, maximumAge: 60) == ["fresh"])
    }

    @Test
    func `legacy migration cannot overwrite a concurrent current snapshot`() throws {
        let fixture = try snapshotFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try JSONEncoder().encode(["legacy"]).write(to: fixture.file)
        let replacement = fixture.directory.appending(path: "replacement.json")
        try Data(#"{"schemaVersion":1,"payload":["fresh"]}"#.utf8).write(to: replacement)
        let cache = DiskCache(
            directoryName: fixture.cache.directoryName,
            logger: Logger(subsystem: "tests", category: "cache"),
            maximumSnapshotBytes: fixture.cache.maximumSnapshotBytes,
            afterSnapshotRead: {},
            beforeLegacyMigration: {
                _ = rename(replacement.path, fixture.file.path)
            }
        )

        #expect(cache.load([String].self, kind: "pads", account: fixture.account, maximumAge: 60) == ["legacy"])
        #expect(cache.load([String].self, kind: "pads", account: fixture.account, maximumAge: 60) == ["fresh"])
    }

    private func snapshotFixture() throws -> (
        cache: DiskCache, directory: URL, file: URL, account: UUID
    ) {
        let directoryName = "com.buddyappkit.tests.DiskCache-\(UUID().uuidString)"
        let account = UUID()
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "pads-\(account.uuidString).json")
        return (cache, directory, file, account)
    }

    @Test
    func `deletion reports success and remains idempotent`() {
        let directoryName = "com.buddyappkit.tests.DiskCache-\(UUID().uuidString)"
        let account = UUID()
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))
        cache.save(["value"], kind: "pads", account: account)

        #expect(cache.delete(kind: "pads", account: account))
        #expect(cache.delete(kind: "pads", account: account))
        #expect(!cache.delete(kind: "../invalid", account: account))
    }

    @Test
    func `directory creation failure is not reported as a missing snapshot`() throws {
        let directoryName = "com.buddyappkit.tests.DiskCache-\(UUID().uuidString)"
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let blockedDirectory = base.appending(path: directoryName)
        try Data("blocking file".utf8).write(to: blockedDirectory)
        defer { try? FileManager.default.removeItem(at: blockedDirectory) }
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))

        guard case .unavailable = cache.loadResult(
            [String].self, kind: "pads", account: UUID(), maximumAge: 60
        ) else {
            Issue.record("Expected directory failure to be unavailable, not missing")
            return
        }
    }

    @Test
    func `expired snapshots are reported without decoding`() throws {
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
        let written = Date(timeIntervalSince1970: 1000)
        try FileManager.default.setAttributes([.modificationDate: written], ofItemAtPath: file.path)

        guard case let .stale(modificationDate) = cache.loadResult(
            [String].self,
            kind: "pads",
            account: account,
            maximumAge: 30,
            now: written.addingTimeInterval(31)
        ) else {
            Issue.record("Expected the expired snapshot to be reported as stale")
            return
        }

        #expect(abs(modificationDate.timeIntervalSince(written)) < 0.000_001)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func `fresh snapshots return their modification date`() throws {
        let directoryName = "com.buddyappkit.tests.DiskCache-\(UUID().uuidString)"
        let account = UUID()
        let cache = DiskCache(directoryName: directoryName, logger: Logger(subsystem: "tests", category: "cache"))
        let base = try #require(FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first)
        let directory = base.appending(path: directoryName, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        cache.save(["fresh"], kind: "pads", account: account)
        guard case let .value(written) = cache.modificationDate(kind: "pads", account: account) else {
            Issue.record("Expected snapshot metadata")
            return
        }
        guard case let .value(value, modificationDate) = cache.loadResult(
            [String].self,
            kind: "pads",
            account: account,
            maximumAge: 30,
            now: written.addingTimeInterval(30)
        ) else {
            Issue.record("Expected the snapshot at the age boundary to remain fresh")
            return
        }

        #expect(value == ["fresh"])
        #expect(abs(modificationDate.timeIntervalSince(written)) < 0.000_001)
    }
}
