import Foundation
import os
#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

nonisolated extension DiskCache {
    static func modificationDate(from metadata: stat) -> Date {
        #if canImport(Darwin)
            let timestamp = metadata.st_mtimespec
        #else
            let timestamp = metadata.st_mtim
        #endif
        return Date(
            timeIntervalSince1970: TimeInterval(timestamp.tv_sec) + TimeInterval(timestamp.tv_nsec) / 1_000_000_000
        )
    }

    func logUnavailable(operation: String, kind: String, error: any Error) {
        let reason = error.localizedDescription
        logger.error(
            "Failed to \(operation, privacy: .public) \(kind, privacy: .public) cache: \(reason, privacy: .public)"
        )
    }

    func quarantineIfUnchanged(_ url: URL, identity: FileIdentity, kind: String) {
        var current = stat()
        guard lstat(url.path, &current) == 0, FileIdentity(current) == identity else { return }

        let quarantine = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).corrupt-\(UUID().uuidString)")
        guard rename(url.path, quarantine.path) == 0 else {
            logger.error("Could not quarantine corrupt \(kind, privacy: .public) cache")
            return
        }

        var moved = stat()
        guard lstat(quarantine.path, &moved) == 0 else { return }

        if FileIdentity(moved) == identity {
            try? FileManager.default.removeItem(at: quarantine)
        } else {
            do {
                try FileManager.default.moveItem(at: quarantine, to: url)
            } catch {
                logger.error("A replaced \(kind, privacy: .public) cache was preserved in quarantine: \(error)")
            }
        }
    }

    func migrateIfUnchanged(
        _ value: some Codable, at url: URL, identity: FileIdentity, kind: String
    ) {
        let envelope = Envelope(schemaVersion: Self.schemaVersion, payload: value)
        guard let data = try? JSONEncoder().encode(envelope) else { return }

        var current = stat()
        guard lstat(url.path, &current) == 0, FileIdentity(current) == identity else { return }

        let suffix = UUID().uuidString
        let backup = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).legacy-\(suffix)")
        let temporary = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).migrate-\(suffix)")
        guard rename(url.path, backup.path) == 0 else { return }

        var moved = stat()
        guard lstat(backup.path, &moved) == 0, FileIdentity(moved) == identity else {
            restoreIfAbsent(backup, to: url, kind: kind)
            return
        }

        do {
            try data.write(to: temporary, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if link(temporary.path, url.path) == 0 || errno == EEXIST {
                try? FileManager.default.removeItem(at: backup)
            } else {
                logger.error("Could not publish migrated \(kind, privacy: .public) cache")
                restoreIfAbsent(backup, to: url, kind: kind)
            }
        } catch {
            logger.error("Could not migrate \(kind, privacy: .public) cache: \(error)")
            restoreIfAbsent(backup, to: url, kind: kind)
        }
        try? FileManager.default.removeItem(at: temporary)
    }

    private func restoreIfAbsent(_ source: URL, to destination: URL, kind: String) {
        if link(source.path, destination.path) == 0 {
            try? FileManager.default.removeItem(at: source)
        } else if errno != EEXIST {
            logger.error("A concurrently replaced \(kind, privacy: .public) cache remains quarantined")
        }
    }
}
