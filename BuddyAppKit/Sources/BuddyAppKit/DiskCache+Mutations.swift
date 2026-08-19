import Foundation
import os

public nonisolated extension DiskCache {
    func save(_ value: some Codable, kind: String, account: UUID) {
        do {
            let url = try resolvedURL(kind: kind, account: account)
            let generation = Self.mutations.generation(for: url)
            let envelope = Envelope(schemaVersion: Self.schemaVersion, payload: value)
            let data = try JSONEncoder().encode(envelope)
            beforeSavePublish()
            try Self.mutations.publishIfCurrent(url: url, generation: generation) {
                var wroteFile = false
                do {
                    try data.write(to: url, options: .atomic)
                    wroteFile = true
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                } catch {
                    if wroteFile {
                        try? FileManager.default.removeItem(at: url)
                    }
                    throw error
                }
            }
        } catch {
            let reason = error.localizedDescription
            logger.error("Failed to write \(kind, privacy: .public) cache: \(reason, privacy: .public)")
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
