//
//  MCPClientInstall.swift
//  coderpad
//
//  One-click "Add to <client>" for the MCP settings pane (#501): instead of copying a
//  Terminal command, write the PadBuddy server entry straight into the client's config,
//  merging with anything already there.
//
//  The app is sandboxed, so it can't reach a client's config folder on its own. The user
//  grants access to that folder once through an open panel (the URL it returns is
//  security-scoped); we read, merge, and write within that scope. This is a one-time setup
//  action, so we don't persist a bookmark - a fresh grant per use keeps it simple and needs
//  no extra entitlement.
//

import MCPKit

#if os(macOS)
    import AppKit
#else
    import Foundation
#endif

enum MCPClientInstall {
    enum JSONConfigError: LocalizedError {
        case incompatibleMCPServers

        var errorDescription: String? {
            switch self {
            case .incompatibleMCPServers:
                "The existing mcpServers value is not a JSON object. PadBuddy left the config unchanged."
            }
        }
    }

    /// An MCP client PadBuddy can install itself into.
    enum Client: String, CaseIterable, Identifiable {
        case claudeDesktop
        case claudeCode
        case codex
        case cursor

        var id: String {
            rawValue
        }

        var displayName: String {
            switch self {
            case .claudeDesktop: "Claude Desktop"
            case .claudeCode: "Claude Code"
            case .codex: "Codex"
            case .cursor: "Cursor"
            }
        }

        /// The config file, shown in the manual instructions and written by the button.
        var configPath: String {
            switch self {
            case .claudeDesktop: "~/Library/Application Support/Claude/claude_desktop_config.json"
            case .claudeCode: "~/.claude.json"
            case .codex: "~/.codex/config.toml"
            case .cursor: "~/.cursor/mcp.json"
            }
        }

        /// How to make the client pick up the new server.
        var restartHint: String {
            switch self {
            case .claudeDesktop: "Quit Claude Desktop with \u{2318}Q and reopen it, then ask it about your pads."
            case .claudeCode: "Start a fresh Claude Code session (or run /mcp), then ask it about your pads."
            case .codex: "Restart Codex, then ask it about your pads."
            case .cursor: "Reload Cursor (or toggle the server in its MCP settings), then ask it about your pads."
            }
        }

        /// An optional client-specific tip for confirming the server connected.
        var verifyHint: String? {
            switch self {
            case .claudeDesktop: "If it doesn't show up, check Claude Desktop's logs in ~/Library/Logs/Claude/."
            case .claudeCode: "Confirm it connected with `claude mcp list` or `claude mcp get padbuddy`."
            case .codex, .cursor: nil
            }
        }

        /// The config snippet to paste by hand, for the "edit the file yourself" fallback.
        /// Delegates to MCPKit's `MCPClient` for the `padbuddy` server. Codex gets the
        /// `[mcp_servers.padbuddy]` TOML table and Claude Desktop / Cursor get the `mcpServers`
        /// JSON block, as before.
        ///
        /// Claude Code is mapped to the JSON block too (`MCPClient.claudeDesktop`) rather
        /// than to MCPKit's `.claudeCode`, which emits a `claude mcp add …` shell command:
        /// this pane's copy says "edit ~/.claude.json yourself" and shows that file path, so a
        /// JSON snippet is what matches - preserving the previous behaviour exactly.
        func snippet(executablePath: String) -> String {
            let mapped: MCPClient? = switch self {
            case .claudeDesktop: .claudeDesktop
            case .claudeCode: .claudeDesktop // JSON block for ~/.claude.json, not the CLI command
            case .codex: .codex
            case .cursor: .cursor
            }
            return mapped?.configSnippet(command: executablePath, serverName: "padbuddy") ?? ""
        }
    }

    // The actual config-writing machinery is macOS-only: it drives an `NSOpenPanel`
    // to grant sandboxed access to a desktop client's config folder and reports the
    // outcome with an `NSAlert`. None of those (nor the notion of installing into a
    // local Mac MCP client) has an iOS counterpart, so the install side is gated to
    // macOS. The `Client` data model above stays cross-platform.

    #if !os(macOS)
        /// iOS: no desktop MCP client to install into, and no open-panel/sandbox-grant
        /// flow, so this is a no-op that keeps the call site (`MCPInstallTabs`) compiling.
        @MainActor
        static func install(_: Client, executablePath _: String) async {}
    #endif

    #if os(macOS)
        /// The folder to ask the user to grant, the config file inside it, the format, and the
        /// message explaining why. Claude Code's config sits directly in the home folder, so
        /// that's what gets granted.
        private struct ConfigSpec {
            let preferred: URL?
            let fallback: URL?
            let fileName: String
            let isTOML: Bool
            let message: String
        }

        @MainActor
        private static func spec(for client: Client) -> ConfigSpec {
            let home = realHomeDirectory
            let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
            switch client {
            case .claudeDesktop:
                return ConfigSpec(
                    preferred: support.appendingPathComponent("Claude", isDirectory: true),
                    fallback: support, fileName: "claude_desktop_config.json", isTOML: false,
                    message: "Select Claude Desktop's \u{201C}Claude\u{201D} folder so PadBuddy can add itself."
                )

            case .claudeCode:
                return ConfigSpec(
                    preferred: home, fallback: home, fileName: ".claude.json", isTOML: false,
                    message: "Select your Home folder so PadBuddy can add itself to ~/.claude.json."
                )

            case .codex:
                return ConfigSpec(
                    preferred: home.appendingPathComponent(".codex", isDirectory: true),
                    fallback: home, fileName: "config.toml", isTOML: true,
                    message: "Select the \u{201C}.codex\u{201D} folder so PadBuddy can add itself to config.toml."
                )

            case .cursor:
                return ConfigSpec(
                    preferred: home.appendingPathComponent(".cursor", isDirectory: true),
                    fallback: home, fileName: "mcp.json", isTOML: false,
                    message: "Select the \u{201C}.cursor\u{201D} folder so PadBuddy can add itself to mcp.json."
                )
            }
        }

        /// Adds (or updates) the PadBuddy entry in `client`'s config, preserving anything else
        /// there, then reports the outcome with an alert. The config file reads and writes run
        /// off the main actor so the UI never blocks on disk (#2270).
        @MainActor
        static func install(_ client: Client, executablePath: String) async {
            let spec = spec(for: client)
            guard let folder = grantFolderAccess(
                preferred: spec.preferred,
                fallback: spec.fallback,
                message: spec.message
            ) else { return }

            let accessing = folder.startAccessingSecurityScopedResource()
            defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

            let url = folder.appendingPathComponent(spec.fileName)
            do {
                if spec.isTOML {
                    try await upsertCodexServer(into: url, client: client, executablePath: executablePath)
                } else {
                    try await mergeJSONServer(into: url, client: client, executablePath: executablePath)
                }
            } catch {
                showAlert(.warning, "Couldn't update \(client.displayName)", error.localizedDescription)
            }
        }

        // MARK: - JSON config (Claude Desktop, Claude Code, Cursor)

        /// Adds the PadBuddy entry to `client`'s `mcpServers`, or - when one is already there -
        /// rewrites it (after the user confirms) so its command points at this copy of PadBuddy,
        /// preserving anything else in the file. Reports the outcome itself; does nothing and shows
        /// no alert if the user cancels the update. The read/merge/serialize and the write both
        /// happen off the main actor; only the dialogs run on it (#2270).
        @MainActor
        private static func mergeJSONServer(into url: URL, client: Client, executablePath: String) async throws {
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
                try data.write(to: url, options: .atomic)
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

            let alreadyPresent = servers["padbuddy"] != nil
            servers["padbuddy"] = ["command": executablePath, "args": ["--mcp"]]
            root["mcpServers"] = servers
            return (root, alreadyPresent)
        }

        /// Reads and parses the existing JSON config, returning an empty object when the file is
        /// absent or empty. A malformed file throws so we don't silently clobber it.
        nonisolated private static func existingJSON(at url: URL) throws -> [String: Any] {
            guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { return [:] }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }

            return object
        }

        // MARK: - TOML config (Codex)

        /// Adds a `[mcp_servers.padbuddy]` table, or - when one is already there - rewrites it (after
        /// the user confirms) so its command points at this copy of PadBuddy. Reports the outcome
        /// itself; does nothing and shows no alert if the user cancels the update.
        ///
        /// Read failures throw (only a genuinely absent file counts as empty) so an unreadable
        /// config is never silently replaced, matching the JSON path's behaviour. The file is
        /// read, scanned once (detect + replaceable range in the same pass, #2264), and written
        /// off the main actor; only the dialogs run on it (#2270).
        @MainActor
        private static func upsertCodexServer(into url: URL, client: Client, executablePath: String) async throws {
            let block = codexServerBlock(executablePath: executablePath)
            let (text, scan) = try await Task.detached(priority: .userInitiated) {
                var text = ""
                if FileManager.default.fileExists(atPath: url.path) {
                    text = try String(contentsOf: url, encoding: .utf8)
                }
                return (text, scanCodexConfig(text))
            }.value
            switch scan.declaration {
            case .notDeclared:
                let merged = text.isEmpty ? block : text + "\n" + block
                try await Task.detached(priority: .userInitiated) {
                    try merged.write(to: url, atomically: true, encoding: .utf8)
                }.value
                showAlert(.informational, "Added to \(client.displayName)", client.restartHint)

            case .table:
                guard confirmUpdate(client), let range = scan.tableLineRange else { return }

                var lines = scan.lines
                lines.replaceSubrange(range, with: block.components(separatedBy: "\n"))
                let updated = lines.joined(separator: "\n")
                try await Task.detached(priority: .userInitiated) {
                    try updated.write(to: url, atomically: true, encoding: .utf8)
                }.value
                showAlert(.informational, "Updated \(client.displayName)", client.restartHint)

            case .other:
                // Appending a second [mcp_servers.padbuddy] table would redefine the key and
                // could make the whole config unparseable, so leave the file untouched.
                throw CodexConfigError(errorDescription:
                    "config.toml already declares the \u{201C}padbuddy\u{201D} server in a style "
                        + "PadBuddy can't safely rewrite. Edit its command in config.toml yourself.")
            }
        }

        // MARK: - Access + alerts

        /// The user's REAL home directory. In a sandboxed app `FileManager`'s home and
        /// Application Support point inside the app container (~/Library/Containers/…), so
        /// pre-pointing the panel there sends the user - and the written file - into the
        /// container instead of the actual client config (the whole reason the button looked
        /// like it did nothing). `getpwuid` returns the true home regardless of the sandbox.
        private static var realHomeDirectory: URL {
            if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
                return URL(fileURLWithPath: String(cString: home), isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
        }

        /// Prompts for access to a config folder, pre-pointed at its standard location so the
        /// user usually just confirms. Returns nil if they cancel.
        @MainActor
        private static func grantFolderAccess(preferred: URL?, fallback: URL?, message: String) -> URL? {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Grant Access"
            panel.message = message
            if let preferred, FileManager.default.fileExists(atPath: preferred.path) {
                panel.directoryURL = preferred
            } else {
                panel.directoryURL = fallback
            }

            return panel.runModal() == .OK ? panel.url : nil
        }

        /// Asks whether to overwrite an already-configured `padbuddy` server (e.g. its path changed).
        /// Returns true only if the user picks Update.
        @MainActor
        private static func confirmUpdate(_ client: Client) -> Bool {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Update \(client.displayName)?"
            alert.informativeText = "\(client.displayName) already has a \u{201C}padbuddy\u{201D} server. "
                + "Update it to launch this copy of PadBuddy?"
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }

        @MainActor
        private static func showAlert(_ style: NSAlert.Style, _ title: String, _ message: String) {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = title
            alert.informativeText = message
            alert.runModal()
        }
    #endif
}
