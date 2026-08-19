//
//  DiskCache.swift
//  BuddyAppKit
//
//  On-disk JSON backing for per-account list caches, with the cache directory and
//  logger injected so each app picks its own location (#512). Lifted from the
//  coderpad app. Snapshots live in Application Support, one JSON file per account +
//  kind; the encoder/decoder pair is symmetric (default strategies), so it
//  round-trips the API models faithfully without depending on the API's date format.
//

import Foundation
import os
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public nonisolated enum DiskCacheLoadResult<Value> {
    case missing
    case value(Value, modificationDate: Date)
    case stale(modificationDate: Date)
    case corrupt
    case unavailable
}

public nonisolated enum DiskCacheModificationDateResult {
    case missing
    case value(Date)
    case corrupt
    case unavailable
}

public nonisolated struct DiskCache: Sendable {
    static let schemaVersion = 1
    /// Filesystems and clocks can differ slightly, but a larger lead is not a
    /// trustworthy freshness signal.
    static let maximumFutureModificationSkew: TimeInterval = 5 * 60
    static let mutations = DiskCacheMutationCoordinator()

    struct Envelope<Value: Codable>: Codable {
        let schemaVersion: Int
        let payload: Value
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    private struct Snapshot {
        let data: Data
        let modificationDate: Date
        let identity: FileIdentity
    }

    struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t

        init(_ metadata: stat) {
            device = metadata.st_dev
            inode = metadata.st_ino
        }
    }

    /// The Application-Support-relative directory snapshots live under (e.g.
    /// "com.example.app/DataCache"). Injected so each app keeps its own location.
    public let directoryName: String
    /// Maximum bytes consumed from one snapshot. Reads stop after at most one
    /// extra byte so an oversized cache is rejected without being materialized.
    public let maximumSnapshotBytes: Int
    let logger: Logger
    private let afterSnapshotRead: @Sendable () -> Void
    private let beforeCorruptCleanup: @Sendable () -> Void
    private let beforeLegacyMigration: @Sendable () -> Void
    let beforeSavePublish: @Sendable () -> Void
    let setSaveFilePermissions: @Sendable (URL) throws -> Void

    public init(directoryName: String, logger: Logger, maximumSnapshotBytes: Int = 10_000_000) {
        self.init(
            directoryName: directoryName,
            logger: logger,
            maximumSnapshotBytes: maximumSnapshotBytes,
            afterSnapshotRead: {},
            beforeCorruptCleanup: {},
            beforeLegacyMigration: {},
            beforeSavePublish: {},
            setSaveFilePermissions: Self.setPrivateFilePermissions
        )
    }

    init(
        directoryName: String,
        logger: Logger,
        maximumSnapshotBytes: Int,
        afterSnapshotRead: @escaping @Sendable () -> Void,
        beforeCorruptCleanup: @escaping @Sendable () -> Void = {},
        beforeLegacyMigration: @escaping @Sendable () -> Void = {},
        beforeSavePublish: @escaping @Sendable () -> Void = {},
        setSaveFilePermissions: @escaping @Sendable (URL) throws -> Void = Self.setPrivateFilePermissions
    ) {
        self.directoryName = directoryName
        self.logger = logger
        self.maximumSnapshotBytes = max(0, maximumSnapshotBytes)
        self.afterSnapshotRead = afterSnapshotRead
        self.beforeCorruptCleanup = beforeCorruptCleanup
        self.beforeLegacyMigration = beforeLegacyMigration
        self.beforeSavePublish = beforeSavePublish
        self.setSaveFilePermissions = setSaveFilePermissions
    }

    private static func setPrivateFilePermissions(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Cache kinds become filename prefixes, so accept only a short ASCII token.
    /// Rejecting separators and punctuation keeps every operation in this cache's
    /// directory even when a caller supplies an untrusted kind (#1263).
    static func isValidKind(_ kind: String) -> Bool {
        !kind.isEmpty && kind.utf8.count <= 64 && kind.utf8.allSatisfy { byte in
            switch byte {
            case 45, 48 ... 57, 65 ... 90, 95, 97 ... 122: true
            default: false
            }
        }
    }

    /// Allows a short hierarchy such as `com.example.app/DataCache`, but no empty,
    /// absolute, traversal, escaped, or platform-specific path components (#1264).
    static func isValidDirectoryName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 256 else { return false }

        return name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
            guard !component.isEmpty, component != ".", component != ".." else { return false }

            return component.utf8.allSatisfy { byte in
                switch byte {
                case 45 ... 46, 48 ... 57, 65 ... 90, 95, 97 ... 122: true
                default: false
                }
            }
        }
    }

    public func load<T: Codable>(_: T.Type, kind: String, account: UUID, maximumAge: TimeInterval) -> T? {
        guard case let .value(value, _) = loadResult(
            T.self,
            kind: kind,
            account: account,
            maximumAge: maximumAge
        ) else { return nil }

        return value
    }

    public func loadResult<T: Codable>(
        _: T.Type,
        kind: String,
        account: UUID,
        maximumAge: TimeInterval,
        now: Date = Date()
    ) -> DiskCacheLoadResult<T> {
        guard maximumAge.isFinite, maximumAge >= 0 else {
            logger.error("Refusing to load cache with an invalid maximum age")
            return .unavailable
        }
        guard let url = resolvedURLForLoad(kind: kind, account: account) else { return .unavailable }

        let snapshot: Snapshot
        do {
            snapshot = try readSnapshot(at: url)
        } catch let error as DiskCacheReadError {
            return readFailure(error, kind: kind)
        } catch {
            logUnavailable(operation: "read", kind: kind, error: error)
            return .unavailable
        }

        if snapshot.modificationDate.timeIntervalSince(now) > Self.maximumFutureModificationSkew {
            logger.error("Discarding future-dated \(kind, privacy: .public) cache")
            beforeCorruptCleanup()
            quarantineIfUnchanged(url, identity: snapshot.identity, kind: kind)
            return .corrupt
        }

        if max(0, now.timeIntervalSince(snapshot.modificationDate)) > maximumAge {
            return .stale(modificationDate: snapshot.modificationDate)
        }

        do {
            let decoder = JSONDecoder()
            if let version = try? decoder.decode(VersionProbe.self, from: snapshot.data).schemaVersion {
                guard version == Self.schemaVersion else {
                    logger.error("Discarding unsupported version \(version) of \(kind, privacy: .public) cache")
                    beforeCorruptCleanup()
                    quarantineIfUnchanged(url, identity: snapshot.identity, kind: kind)
                    return .corrupt
                }

                let envelope = try decoder.decode(Envelope<T>.self, from: snapshot.data)
                return .value(envelope.payload, modificationDate: snapshot.modificationDate)
            }

            // Version 0 snapshots stored the payload directly. Accept them once,
            // then atomically rewrite them in the current envelope format.
            let value = try decoder.decode(T.self, from: snapshot.data)
            beforeLegacyMigration()
            migrateIfUnchanged(value, at: url, identity: snapshot.identity, kind: kind)
            return .value(value, modificationDate: snapshot.modificationDate)
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to decode \(kind, privacy: .public) cache: \(reason, privacy: .public)")
            // A cache is disposable and cannot heal while corrupt bytes remain.
            // Remove it after reporting a recoverable status so subsequent reads
            // become ordinary misses and a fresh network result can replace it.
            beforeCorruptCleanup()
            quarantineIfUnchanged(url, identity: snapshot.identity, kind: kind)
            return .corrupt
        }
    }

    private func readFailure<T>(_ error: DiskCacheReadError, kind: String) -> DiskCacheLoadResult<T> {
        switch error {
        case .missing:
            return .missing

        case .tooLarge:
            logger.error(
                "Ignoring oversized \(kind, privacy: .public) cache: limit is \(maximumSnapshotBytes) bytes"
            )
            return .unavailable

        case .unsafeFile:
            logger.error("Ignoring non-regular or symbolic-link \(kind, privacy: .public) cache")
            return .unavailable
        }
    }

    private func resolvedURLForLoad(kind: String, account: UUID) -> URL? {
        do {
            return try resolvedURL(kind: kind, account: account)
        } catch {
            logUnavailable(operation: "resolve", kind: kind, error: error)
            return nil
        }
    }

    private func readSnapshot(at url: URL) throws -> Snapshot {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw DiskCacheReadError.missing
            }
            if errno == ELOOP {
                throw DiskCacheReadError.unsafeFile
            }
            throw CocoaError(.fileReadUnknown)
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            throw DiskCacheReadError.unsafeFile
        }

        let readCeiling = maximumSnapshotBytes == Int.max ? Int.max : maximumSnapshotBytes + 1
        var data = Data()
        while data.count < readCeiling {
            let bytesToRead = min(64 * 1024, readCeiling - data.count)
            guard let chunk = try handle.read(upToCount: bytesToRead),
                  !chunk.isEmpty else { break }

            data.append(chunk)
        }
        guard data.count <= maximumSnapshotBytes else {
            throw DiskCacheReadError.tooLarge
        }

        afterSnapshotRead()
        guard fstat(descriptor, &metadata) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }

        return Snapshot(
            data: data,
            modificationDate: Self.modificationDate(from: metadata),
            identity: FileIdentity(metadata)
        )
    }

    /// When the snapshot for `kind`+`account` was last written, or nil if there's no file.
    /// Lets a reader (e.g. the headless MCP server, #520) judge freshness without loading
    /// and decoding the whole snapshot.
    public func modificationDate(kind: String, account: UUID) -> DiskCacheModificationDateResult {
        let url: URL
        do {
            url = try resolvedURL(kind: kind, account: account)
        } catch {
            logUnavailable(operation: "resolve metadata", kind: kind, error: error)
            return .unavailable
        }
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return .missing
            }
            if errno == ELOOP {
                return .corrupt
            }
            return .unavailable
        }

        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else { return .unavailable }
        guard metadata.st_mode & S_IFMT == S_IFREG else { return .corrupt }

        return .value(Self.modificationDate(from: metadata))
    }
}

private enum DiskCacheReadError: Error {
    case missing
    case unsafeFile
    case tooLarge
}
