//
//  MCPClientInstall+Write.swift
//  coderpad
//
//  How the MCP installer replaces a client's configuration file: validating the
//  command it is about to write, preserving the file's metadata, and leaving a
//  recoverable copy. Split from MCPClientInstall.swift for file length.
//

import Foundation

extension MCPClientInstall {
    /// Whether `path` is something the client can actually execute: present, a
    /// regular file (not a directory or a dangling symlink), and executable.
    nonisolated static func isRunnableExecutable(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }

        var isDirectory: ObjCBool = false
        let manager = FileManager.default
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        return manager.isExecutableFile(atPath: path)
    }

    /// Suffix for the copy left beside a config before PadBuddy rewrites it.
    nonisolated static let backupSuffix = ".padbuddy-backup"

    /// Replaces a client's config file, keeping its metadata and leaving a copy of
    /// what was there.
    ///
    /// A plain atomic write creates a fresh file and renames it over the target,
    /// which silently drops the original's POSIX mode, ACLs, and extended
    /// attributes — so updating a deliberately protected config could weaken or
    /// break its access setup (#2533, #2534). `replaceItemAt` carries that
    /// metadata onto the replacement instead, and its `backupItemName` leaves the
    /// previous contents beside the file so a rewrite defect or an interrupted
    /// write is recoverable rather than final (#2535).
    ///
    /// A file that doesn't exist yet has no metadata to keep and nothing to back
    /// up, so it takes the plain write.
    nonisolated static func writeConfig(_ data: Data, to url: URL) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else {
            try data.write(to: url, options: .atomic)
            return
        }

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".padbuddy-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        do {
            _ = try manager.replaceItemAt(
                url,
                withItemAt: temporary,
                backupItemName: url.lastPathComponent + backupSuffix,
                options: [.withoutDeletingBackupItem]
            )
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }
}
