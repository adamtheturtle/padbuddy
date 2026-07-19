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

public nonisolated struct DiskCache: Sendable {
    /// The Application-Support-relative directory snapshots live under (e.g.
    /// "com.example.app/DataCache"). Injected so each app keeps its own location.
    public let directoryName: String
    private let logger: Logger

    public init(directoryName: String, logger: Logger) {
        self.directoryName = directoryName
        self.logger = logger
    }

    private func url(kind: String, account: UUID) -> URL? {
        guard Self.isValidKind(kind) else { return nil }
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }

        let dir = base.appending(path: directoryName, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
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

    public func load<T: Decodable>(_: T.Type, kind: String, account: UUID) -> T? {
        guard let url = url(kind: kind, account: account),
              let data = try? Data(contentsOf: url) else { return nil }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to decode \(kind, privacy: .public) cache: \(reason, privacy: .public)")
            return nil
        }
    }

    public func save(_ value: some Encodable, kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }

        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to write \(kind, privacy: .public) cache: \(reason, privacy: .public)")
        }
    }

    public func delete(kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }

        try? FileManager.default.removeItem(at: url)
    }

    /// When the snapshot for `kind`+`account` was last written, or nil if there's no file.
    /// Lets a reader (e.g. the headless MCP server, #520) judge freshness without loading
    /// and decoding the whole snapshot.
    public func modificationDate(kind: String, account: UUID) -> Date? {
        guard let url = url(kind: kind, account: account),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }

        return attributes[.modificationDate] as? Date
    }
}
