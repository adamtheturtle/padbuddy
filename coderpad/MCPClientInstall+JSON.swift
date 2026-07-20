//
//  MCPClientInstall+JSON.swift
//  coderpad
//
//  The JSON side of the one-click MCP installer (Claude Desktop, Claude Code,
//  Cursor). Split from MCPClientInstall.swift for file and type-body length.
//

import Foundation

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
                let data = try JSONSerialization.data(
                    withJSONObject: merged.root,
                    options: [.prettyPrinted, .sortedKeys]
                )
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
            var root = root
            var servers: [String: Any]
            if let existing = root["mcpServers"] {
                guard let object = existing as? [String: Any] else {
                    throw JSONConfigError.incompatibleMCPServers
                }

                servers = object
            } else {
                servers = [:]
            }

            let alreadyPresent: Bool
            if let existing = servers["padbuddy"] {
                guard let server = existing as? [String: Any], server["command"] is String,
                      server["args"] == nil || server["args"] is [String]
                else {
                    throw JSONConfigError.incompatiblePadBuddyServer
                }

                alreadyPresent = true
            } else {
                alreadyPresent = false
            }
            servers["padbuddy"] = ["command": executablePath, "args": ["--mcp"]]
            root["mcpServers"] = servers
            return (root, alreadyPresent)
        }

        /// Reads and parses the existing JSON config, returning an empty object when the file is
        /// absent or empty. A malformed file throws so we don't silently clobber it.
        private nonisolated static func existingJSON(at url: URL) throws -> [String: Any] {
            guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

            let data = try Data(contentsOf: url)
            // Whitespace-only counts as blank. A file holding just a newline is empty
            // to the person who made it, and rejecting it as corrupt meant the
            // installer refused to write a config it could perfectly well create
            // (#2532).
            let text = String(bytes: data, encoding: .utf8) ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }

            return object
        }
    }

#endif
