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

public nonisolated struct DiskCache: Sendable {
    private static let schemaVersion = 1

    private struct Envelope<Value: Codable>: Codable {
        let schemaVersion: Int
        let payload: Value
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: Int
    }

    /// The Application-Support-relative directory snapshots live under (e.g.
    /// "com.example.app/DataCache"). Injected so each app keeps its own location.
    public let directoryName: String
    /// Maximum bytes consumed from one snapshot. Reads stop after at most one
    /// extra byte so an oversized cache is rejected without being materialized.
    public let maximumSnapshotBytes: Int
    private let logger: Logger

    public init(directoryName: String, logger: Logger, maximumSnapshotBytes: Int = 10_000_000) {
        self.directoryName = directoryName
        self.logger = logger
        self.maximumSnapshotBytes = max(0, maximumSnapshotBytes)
    }

    private func resolvedURL(kind: String, account: UUID) throws -> URL {
        guard Self.isValidKind(kind), Self.isValidDirectoryName(directoryName) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }

        let dir = base.appending(path: directoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir.appending(path: "\(kind)-\(account.uuidString).json")
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

        let data: Data
        do {
            data = try readSnapshot(at: url)
        } catch let error as DiskCacheReadError {
            return readFailure(error, kind: kind)
        } catch {
            logUnavailable(operation: "read", kind: kind, error: error)
            return .unavailable
        }

        let modificationDate: Date
        do {
            modificationDate = try fileModificationDate(at: url)
        } catch {
            logUnavailable(operation: "inspect", kind: kind, error: error)
            return .unavailable
        }

        if max(0, now.timeIntervalSince(modificationDate)) > maximumAge {
            return .stale(modificationDate: modificationDate)
        }

        do {
            let decoder = JSONDecoder()
            if let version = try? decoder.decode(VersionProbe.self, from: data).schemaVersion {
                guard version == Self.schemaVersion else {
                    logger.error("Discarding unsupported version \(version) of \(kind, privacy: .public) cache")
                    try? FileManager.default.removeItem(at: url)
                    return .corrupt
                }

                let envelope = try decoder.decode(Envelope<T>.self, from: data)
                return .value(envelope.payload, modificationDate: modificationDate)
            }

            // Version 0 snapshots stored the payload directly. Accept them once,
            // then atomically rewrite them in the current envelope format.
            let value = try decoder.decode(T.self, from: data)
            save(value, kind: kind, account: account)
            return .value(value, modificationDate: modificationDate)
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to decode \(kind, privacy: .public) cache: \(reason, privacy: .public)")
            // A cache is disposable and cannot heal while corrupt bytes remain.
            // Remove it after reporting a recoverable status so subsequent reads
            // become ordinary misses and a fresh network result can replace it.
            try? FileManager.default.removeItem(at: url)
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

    private func readSnapshot(at url: URL) throws -> Data {
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
                  !chunk.isEmpty else { return data }

            data.append(chunk)
        }
        guard data.count <= maximumSnapshotBytes else {
            throw DiskCacheReadError.tooLarge
        }

        return data
    }

    public func save(_ value: some Codable, kind: String, account: UUID) {
        var wroteFile = false
        var targetURL: URL?
        do {
            let url = try resolvedURL(kind: kind, account: account)
            targetURL = url
            let envelope = Envelope(schemaVersion: Self.schemaVersion, payload: value)
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: url, options: .atomic)
            wroteFile = true
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Never retain a newly written snapshot if its restrictive attributes
            // could not be applied.
            if wroteFile, let targetURL {
                try? FileManager.default.removeItem(at: targetURL)
            }
            let reason = error.localizedDescription
            logger.error("Failed to write \(kind, privacy: .public) cache: \(reason, privacy: .public)")
        }
    }

    /// Removes a snapshot. Missing files are an idempotent success; validation or
    /// filesystem failures are reported to both the caller and the cache log.
    @discardableResult
    public func delete(kind: String, account: UUID) -> Bool {
        do {
            let url = try resolvedURL(kind: kind, account: account)
            try FileManager.default.removeItem(at: url)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to delete \(kind, privacy: .public) cache: \(reason, privacy: .public)")
            return false
        }
    }

    /// When the snapshot for `kind`+`account` was last written, or nil if there's no file.
    /// Lets a reader (e.g. the headless MCP server, #520) judge freshness without loading
    /// and decoding the whole snapshot.
    public func modificationDate(kind: String, account: UUID) -> Date? {
        guard let url = try? resolvedURL(kind: kind, account: account),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }

        return attributes[.modificationDate] as? Date
    }

    private func fileModificationDate(at url: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attributes[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnknown)
        }

        return date
    }

    private func logUnavailable(operation: String, kind: String, error: any Error) {
        let reason = error.localizedDescription
        logger.error(
            "Failed to \(operation, privacy: .public) \(kind, privacy: .public) cache: \(reason, privacy: .public)"
        )
    }
}

private enum DiskCacheReadError: Error {
    case missing
    case unsafeFile
    case tooLarge
}
