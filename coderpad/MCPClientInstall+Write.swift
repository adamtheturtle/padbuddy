//
//  MCPClientInstall+Write.swift
//  coderpad
//
//  How the MCP installer replaces a client's configuration file: validating the
//  command it is about to write, preserving the file's metadata, and leaving a
//  recoverable copy. Split from MCPClientInstall.swift for file length.
//

import Foundation
import MCPClientInstall

extension MCPClientInstall {
    /// Resolves a parent-folder grant to the exact client configuration folder.
    /// The open panel cannot select a preferred directory that does not exist, so
    /// first-time installs grant its existing parent; create the named child only
    /// after that parent is security-scoped (#1121–#1123).
    static func configurationFolder(
        granted: URL, preferred: URL?, fallback: URL?, fileManager: FileManager = .default
    ) throws -> URL {
        guard let preferred, let fallback,
              granted.standardizedFileURL == fallback.standardizedFileURL,
              preferred.deletingLastPathComponent().standardizedFileURL == fallback.standardizedFileURL,
              !fileManager.fileExists(atPath: preferred.path) else { return granted }

        try fileManager.createDirectory(at: preferred, withIntermediateDirectories: false)
        return preferred
    }

    struct ConfigVerificationError: LocalizedError {
        let errorDescription: String?
    }

    /// Whether `path` is something the client can actually execute: present, a
    /// regular file (not a directory or a dangling symlink), and executable.
    nonisolated static func isRunnableExecutable(_ path: String) -> Bool {
        isRunnableMCPExecutable(atPath: path)
    }

    /// What is sitting at a config path, so the installer can refuse anything it
    /// shouldn't read or replace.
    enum ConfigPathKind: Equatable {
        /// Nothing there yet — the installer will create it.
        case absent
        /// A plain file, the only thing safe to rewrite.
        case regularFile
        /// A symlink. Following it would write somewhere other than the folder the
        /// user granted access to and the UI named (#2546).
        case symbolicLink(destination: String)
        /// A directory, FIFO, socket, or device. Reading or replacing one of these
        /// produces confusing or destructive behaviour, and a FIFO can block the UI
        /// outright (#2545).
        case special
    }

    /// Classifies the config path without following symlinks.
    nonisolated static func configPathKind(at url: URL) -> ConfigPathKind {
        switch classifyMCPConfigurationPath(at: url) {
        case .absent: .absent
        case .regularFile: .regularFile
        case let .symbolicLink(destination): .symbolicLink(destination: destination)
        case .special: .special
        }
    }

    /// The reason the installer won't touch this path, or nil when it is safe.
    ///
    /// `attributesOfItem` does not follow symlinks, so a link is seen as a link
    /// rather than as whatever it points at.
    nonisolated static func refusalReason(for kind: ConfigPathKind, fileName: String) -> String? {
        switch kind {
        case .absent, .regularFile:
            nil

        case let .symbolicLink(destination):
            String(localized: """
            \(fileName) is a link to \(destination.isEmpty ? "another location" : destination). \
            PadBuddy will not write through it, because that would change a file outside the folder \
            you picked. Edit that file directly, or replace the link with a real config file.
            """)

        case .special:
            String(localized: """
            \(fileName) is not a regular file, so PadBuddy cannot read or replace it. \
            Check what's at that path and try again.
            """)
        }
    }

    /// Suffix for the copy left beside a config before PadBuddy rewrites it.
    nonisolated static let backupSuffix = ".padbuddy-backup"

    /// Suffix for the config displaced when the user restores PadBuddy's backup.
    nonisolated static let preRestoreSuffix = ".padbuddy-before-restore"

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
        try writeMCPConfiguration(data, to: url, backupSuffix: backupSuffix)
    }

    /// Restores the side-by-side backup created by `writeConfig`, while retaining
    /// the currently installed config as a second recovery file.
    nonisolated static func restoreConfigBackup(at url: URL) throws {
        let manager = FileManager.default
        let backup = URL(fileURLWithPath: url.path + backupSuffix)
        guard case .regularFile = configPathKind(at: url) else {
            throw ConfigVerificationError(errorDescription:
                "The current configuration is missing or is not a regular file. PadBuddy left it unchanged.")
        }
        guard case .regularFile = configPathKind(at: backup) else {
            throw ConfigVerificationError(errorDescription:
                "No PadBuddy backup was found beside this configuration file.")
        }

        _ = try manager.replaceItemAt(
            url,
            withItemAt: backup,
            backupItemName: url.lastPathComponent + preRestoreSuffix,
            options: [.withoutDeletingBackupItem]
        )
    }

    #if os(macOS)
        /// Reads the file back after replacement and verifies the exact server shape
        /// the JSON clients consume before the installer reports success (#1134).
        nonisolated static func verifyJSONConfig(at url: URL, executablePath: String) throws {
            let root = try readMCPJSONConfiguration(at: url)
            let server = MCPServerSpec(name: "padbuddy", command: executablePath, productName: "PadBuddy")
            guard mcpServerIsConfigured(server, inJSON: root) else {
                throw ConfigVerificationError(errorDescription: verificationRecoveryMessage(
                    problem: "The written JSON configuration did not contain the expected PadBuddy server.",
                    url: url
                ))
            }
        }

        /// Re-scans the written TOML and checks the generated command/arguments
        /// survived the filesystem replacement before showing a success alert.
        nonisolated static func verifyCodexConfig(at url: URL, executablePath: String) throws {
            let text = try String(contentsOf: url, encoding: .utf8)
            let server = MCPServerSpec(name: "padbuddy", command: executablePath, productName: "PadBuddy")
            guard mcpServerIsConfigured(server, inCodexTOML: text) else {
                throw ConfigVerificationError(errorDescription: verificationRecoveryMessage(
                    problem: "The written PadBuddy server table did not preserve its command and arguments.",
                    url: url
                ))
            }
        }

        /// Gives verification failures an actionable, exact recovery path. Existing configs
        /// are backed up beside the rewritten file by `writeConfig`; a first-time config has
        /// no previous contents, so the user can safely remove it and retry.
        nonisolated static func verificationRecoveryMessage(problem: String, url: URL) -> String {
            let backup = url.path + backupSuffix
            if FileManager.default.fileExists(atPath: backup) {
                return "\(problem) Restore the previous file from \(backup), then fix the config and try again."
            }
            return "\(problem) Remove \(url.path), then try again with Add to your assistant."
        }
    #endif
}
