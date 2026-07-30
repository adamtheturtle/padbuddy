//
//  MCPClientInstall+JSON.swift
//  coderpad
//
//  The JSON side of the one-click MCP installer (Claude Desktop, Claude Code,
//  Cursor). Split from MCPClientInstall.swift for file and type-body length.
//

import Foundation
import MCPClientInstall

#if os(macOS)

    import AppKit

    extension MCPClientInstall {
        // MARK: - JSON config (Claude Desktop, Claude Code, Cursor)

        /// Adds the PadBuddy entry to `client`'s `mcpServers`, or - when one is already there -
        /// rewrites it (after the user confirms) so its command points at this copy of PadBuddy,
        /// preserving anything else in the file. Reports the outcome itself; does nothing and shows
        /// no alert if the user cancels the update. The read/merge/serialize and the write both
        /// happen off the main actor; only the dialogs run on it (#2270).
        @MainActor
        static func mergeJSONServer(into url: URL, client: Client, executablePath: String) async throws {
            let (data, alreadyPresent) = try await Task.detached(priority: .userInitiated) {
                let root = try existingJSON(at: url)
                let merged = try jsonConfigByAddingServer(to: root, executablePath: executablePath)
                let data = try serializedMCPJSONConfiguration(merged.root)
                return (data, merged.alreadyPresent)
            }.value
            if alreadyPresent, !confirmUpdate(client) { return }

            try await Task.detached(priority: .userInitiated) {
                try writeConfig(data, to: url)
                try verifyJSONConfig(at: url, executablePath: executablePath)
            }.value

            let title = alreadyPresent ? "Updated \(client.displayName)" : "Added to \(client.displayName)"
            showAlert(.informational, title, client.restartHint)
        }

        nonisolated static func jsonConfigByAddingServer(
            to root: [String: Any],
            executablePath: String
        ) throws -> (root: [String: Any], alreadyPresent: Bool) {
            if let existingServers = root["mcpServers"] {
                guard let servers = existingServers as? [String: Any] else {
                    throw JSONConfigError.incompatibleMCPServers
                }
                if let existing = servers["padbuddy"] {
                    guard let object = existing as? [String: Any],
                          object["command"] is String,
                          object["args"] == nil || object["args"] is [String]
                    else {
                        throw JSONConfigError.incompatiblePadBuddyServer
                    }
                }
            }

            let server = MCPServerSpec(
                name: "padbuddy",
                command: executablePath,
                productName: "PadBuddy"
            )
            let merged = try addingMCPServer(server, toJSON: root)
            return (merged.root, merged.alreadyPresent)
        }

        /// Reads and parses the existing JSON config, returning an empty object when the file is
        /// absent or empty. A malformed file throws so we don't silently clobber it.
        private nonisolated static func existingJSON(at url: URL) throws -> [String: Any] {
            try readMCPJSONConfiguration(at: url)
        }
    }

#endif
