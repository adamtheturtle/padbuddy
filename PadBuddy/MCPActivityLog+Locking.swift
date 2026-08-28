//
//  MCPActivityLog+Locking.swift
//  coderpad
//
//  The advisory file lock every activity-log access is taken under, and the
//  permission restrictions applied with it.
//

import Foundation
import MCPKit
import os
#if canImport(Darwin)
    import Darwin
#endif

nonisolated extension MCPActivityLog {
    /// Runs `operation` under the advisory file lock, or returns nil without running
    /// it when the lock can't be acquired within the bounded wait. The log stores
    /// account display names, so the directory and its files are kept user-private
    /// (0700/0600) as a side effect of taking the lock (#1760).
    @discardableResult
    static func withActivityLogLock<T>(
        in directory: URL, exclusive: Bool, operation: () -> T
    ) -> T? {
        #if canImport(Darwin)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let lockURL = directory.appending(path: lockFileName)
            restrictLogPermissions(in: directory)

            let descriptor = open(
                lockURL.path,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                mode_t(0o600)
            )
            guard descriptor >= 0 else {
                // Never operate on the shared file without the lock: concurrent
                // unlocked writers are exactly how the JSONL tears (#1756).
                return nil
            }

            defer { close(descriptor) }

            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  fchmod(descriptor, 0o600) == 0 else { return nil }

            // Bounded, non-blocking acquisition: a stalled headless process holding
            // the lock must not freeze Settings actions running on the main actor
            // (#1757), and a failed lock must skip the operation rather than write
            // concurrently (#1756).
            let kind = exclusive ? LOCK_EX : LOCK_SH
            var acquired = flock(descriptor, kind | LOCK_NB) == 0
            var attempts = 0
            while !acquired, attempts < 20 {
                usleep(100_000)
                attempts += 1
                acquired = flock(descriptor, kind | LOCK_NB) == 0
            }
            guard acquired else { return nil }

            defer { flock(descriptor, LOCK_UN) }

            return operation()
        #else
            return operation()
        #endif
    }

    /// Keeps the log and lock files user-private: they carry account display names
    /// and activity timing (#1760).
    ///
    /// Opened and verified rather than chmod'ed by path. `setAttributes(ofItemAtPath:)`
    /// follows symlinks, so a link planted at the log path retargeted the 0600 at
    /// whatever it pointed to (#4719).
    private static func restrictLogPermissions(in directory: URL) {
        let logPath = directory.appending(path: "mcp-activity.jsonl").path
        let descriptor = open(logPath, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return }

        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else { return }

        _ = fchmod(descriptor, 0o600)
    }

    /// Atomically replaces the log, creating the replacement 0600 in the first place.
    ///
    /// `Data.write(to:options:.atomic)` writes a fresh file and renames it over the log,
    /// and the new inode takes its mode from the umask — typically 0644 — silently
    /// discarding the restriction `restrictLogPermissions` applied. Since that runs only
    /// when the lock is taken, and `trim` runs on every append, the log spent most of its
    /// life group- and world-readable (#4718). Writing through an explicit `open` also
    /// keeps a symlink at the destination from being followed: the `rename` replaces the
    /// link itself (#4719).
    static func writeRestrictedLog(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appending(path: ".mcp-activity.jsonl.\(UUID().uuidString)")
        let descriptor = open(
            temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600
        )
        guard descriptor >= 0 else { throw activityLogPOSIXError() }

        var wroteFully = false
        defer {
            close(descriptor)
            if !wroteFully {
                try? FileManager.default.removeItem(at: temporary)
            }
        }

        var offset = 0
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }

            while offset < bytes.count {
                let written = pwrite(descriptor, base + offset, bytes.count - offset, off_t(offset))
                guard written > 0 else { throw activityLogPOSIXError() }

                offset += written
            }
        }
        guard fsync(descriptor) == 0 else { throw activityLogPOSIXError() }
        guard rename(temporary.path, url.path) == 0 else { throw activityLogPOSIXError() }

        wroteFully = true
    }

    private static func activityLogPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
