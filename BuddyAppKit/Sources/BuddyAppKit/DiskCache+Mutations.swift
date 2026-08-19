import Foundation
import os
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

public nonisolated extension DiskCache {
    func save(_ value: some Codable, kind: String, account: UUID) {
        do {
            let url = try resolvedURL(kind: kind, account: account)
            let generation = Self.mutations.generation(for: url)
            let envelope = Envelope(schemaVersion: Self.schemaVersion, payload: value)
            let data = try JSONEncoder().encode(envelope)
            let temporaryURL = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try data.write(to: temporaryURL, options: .withoutOverwriting)
            try setSaveFilePermissions(temporaryURL)
            beforeSavePublish()
            try Self.mutations.publishIfCurrent(url: url, generation: generation) {
                try Self.replaceItem(at: url, with: temporaryURL)
            }
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to write \(kind, privacy: .public) cache: \(reason, privacy: .public)")
        }
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Removes a snapshot. Missing files are an idempotent success; validation or
    /// filesystem failures are reported to both the caller and the cache log.
    @discardableResult
    func delete(kind: String, account: UUID) -> Bool {
        do {
            let url = try resolvedURL(kind: kind, account: account)
            try Self.mutations.invalidateAndRun(url: url) {
                try FileManager.default.removeItem(at: url)
            }
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to delete \(kind, privacy: .public) cache: \(reason, privacy: .public)")
            return false
        }
    }
}

final nonisolated class DiskCacheMutationCoordinator: @unchecked Sendable {
    private final class Slot {
        let lock = NSLock()
        var generation: UInt64 = 0
    }

    private let slots = (0 ..< 64).map { _ in Slot() }

    func generation(for url: URL) -> UInt64 {
        let slot = slot(for: url)
        slot.lock.lock()
        defer { slot.lock.unlock() }
        return slot.generation
    }

    func publishIfCurrent(
        url: URL, generation: UInt64, operation: () throws -> Void
    ) rethrows {
        let slot = slot(for: url)
        slot.lock.lock()
        defer { slot.lock.unlock() }
        guard slot.generation == generation else { return }

        try operation()
    }

    func invalidateAndRun(url: URL, operation: () throws -> Void) rethrows {
        let slot = slot(for: url)
        slot.lock.lock()
        defer { slot.lock.unlock() }
        slot.generation &+= 1
        try operation()
    }

    private func slot(for url: URL) -> Slot {
        let path = url.standardizedFileURL.path
        return slots[Int(UInt(bitPattern: path.hashValue) % UInt(slots.count))]
    }
}
