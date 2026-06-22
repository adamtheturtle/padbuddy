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

import AppKit

enum MCPClientInstall {
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

        /// The config snippet to paste by hand, for the "edit the file yourself" fallback.
        func snippet(executablePath: String) -> String {
            switch self {
            case .codex:
                """
                [mcp_servers.coderpad]
                command = "\(executablePath)"
                args = ["--mcp"]
                """

            case .claudeDesktop, .claudeCode, .cursor:
                """
                {
                  "mcpServers": {
                    "coderpad": {
                      "command": "\(executablePath)",
                      "args": ["--mcp"]
                    }
                  }
                }
                """
            }
        }
    }

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
    /// there, then reports the outcome with an alert.
    @MainActor
    static func install(_ client: Client, executablePath: String) {
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
                let added = try appendCodexServer(into: url, executablePath: executablePath)
                if added {
                    showAlert(.informational, "Added to \(client.displayName)", client.restartHint)
                } else {
                    showAlert(.informational, "Already in \(client.displayName)",
                              "\(client.displayName) already has a \u{201C}coderpad\u{201D} server. "
                                  + "Edit \(client.configPath) by hand if its path changed.")
                }
            } else {
                try mergeJSONServer(into: url, executablePath: executablePath)
                showAlert(.informational, "Added to \(client.displayName)", client.restartHint)
            }
        } catch {
            showAlert(.warning, "Couldn't update \(client.displayName)", error.localizedDescription)
        }
    }

    // MARK: - JSON config (Claude Desktop, Claude Code, Cursor)

    private static func mergeJSONServer(into url: URL, executablePath: String) throws {
        var root = try existingJSON(at: url)
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers["coderpad"] = ["command": executablePath, "args": ["--mcp"]]
        root["mcpServers"] = servers

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    /// Reads and parses the existing JSON config, returning an empty object when the file is
    /// absent or empty. A malformed file throws so we don't silently clobber it.
    private static func existingJSON(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        return object
    }

    // MARK: - TOML config (Codex)

    /// Appends a `[mcp_servers.coderpad]` table when one isn't already present, returning
    /// whether it added one (`false` = already configured). Append-only on purpose: it needs
    /// no TOML parser and can never produce a duplicate table (which would be invalid TOML).
    private static func appendCodexServer(into url: URL, executablePath: String) throws -> Bool {
        var text = ""
        if FileManager.default.fileExists(atPath: url.path) {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        guard !text.contains("[mcp_servers.coderpad]") else { return false }

        let block = """
        [mcp_servers.coderpad]
        command = "\(executablePath)"
        args = ["--mcp"]

        """
        let merged = text.isEmpty ? block : text + "\n" + block
        try merged.write(to: url, atomically: true, encoding: .utf8)
        return true
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

    @MainActor
    private static func showAlert(_ style: NSAlert.Style, _ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
