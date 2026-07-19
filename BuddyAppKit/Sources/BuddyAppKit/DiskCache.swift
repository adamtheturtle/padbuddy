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

public nonisolated enum DiskCacheLoadResult<Value> {
    case missing
    case value(Value)
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
    private let logger: Logger

    public init(directoryName: String, logger: Logger) {
        self.directoryName = directoryName
        self.logger = logger
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

    public func load<T: Codable>(_: T.Type, kind: String, account: UUID) -> T? {
        guard case let .value(value) = loadResult(T.self, kind: kind, account: account) else { return nil }

        return value
    }

    public func loadResult<T: Codable>(_: T.Type, kind: String, account: UUID) -> DiskCacheLoadResult<T> {
        let url: URL
        do {
            url = try resolvedURL(kind: kind, account: account)
        } catch {
            logUnavailable(operation: "resolve", kind: kind, error: error)
            return .unavailable
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            logUnavailable(operation: "read", kind: kind, error: error)
            return .unavailable
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
                return .value(envelope.payload)
            }

            // Version 0 snapshots stored the payload directly. Accept them once,
            // then atomically rewrite them in the current envelope format.
            let value = try decoder.decode(T.self, from: data)
            save(value, kind: kind, account: account)
            return .value(value)
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
            if wroteFile, let targetURL { try? FileManager.default.removeItem(at: targetURL) }
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

    private func logUnavailable(operation: String, kind: String, error: any Error) {
        let reason = error.localizedDescription
        logger.error(
            "Failed to \(operation, privacy: .public) \(kind, privacy: .public) cache: \(reason, privacy: .public)"
        )
    }
}
