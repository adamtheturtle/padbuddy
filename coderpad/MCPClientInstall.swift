//
//  MCPClientInstall.swift
//  coderpad
//
//  One-click "Add to <client>" for the MCP settings pane (#501): instead of copying a
//  Terminal command, write the PadBuddy server entry straight into the client's config,
//  merging with anything already there.
//
//  The app is sandboxed, so it can't reach the client's config folder on its own. The user
//  grants access to that folder once through an open panel (the URL it returns is
//  security-scoped); we read, merge, and write within that scope. This is a one-time setup
//  action, so we don't persist a bookmark — a fresh grant per use keeps it simple and needs
//  no extra entitlement.
//
//  Claude Code is deliberately not here: its config (~/.claude.json) is a hidden file in the
//  home directory, so a sandboxed write would mean granting the whole home folder for one
//  file. The `claude mcp add` command stays the path for it.
//

import AppKit

enum MCPClientInstall {
    /// Adds (or updates) the PadBuddy entry in Claude Desktop's JSON config, preserving any
    /// other MCP servers, then reports the outcome.
    @MainActor
    static func addToClaudeDesktop(executablePath: String) {
        let support = realHomeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        guard let folder = grantFolderAccess(
            preferred: support.appendingPathComponent("Claude", isDirectory: true),
            fallback: support,
            message: "Select Claude Desktop's \u{201C}Claude\u{201D} folder so PadBuddy can add "
                + "itself to its configuration."
        ) else { return }

        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        do {
            try mergeJSONServer(into: folder.appendingPathComponent("claude_desktop_config.json"),
                                executablePath: executablePath)
            showAlert(.informational, "Added to Claude Desktop",
                      "Quit Claude Desktop with \u{2318}Q and reopen it, then ask it about your pads.")
        } catch {
            showAlert(.warning, "Couldn't update Claude Desktop", error.localizedDescription)
        }
    }

    /// Adds a `[mcp_servers.coderpad]` table to the Codex CLI's TOML config if one isn't
    /// already present, then reports the outcome.
    @MainActor
    static func addToCodex(executablePath: String) {
        let home = realHomeDirectory
        guard let folder = grantFolderAccess(
            preferred: home.appendingPathComponent(".codex", isDirectory: true),
            fallback: home,
            message: "Select the \u{201C}.codex\u{201D} folder so PadBuddy can add itself to config.toml."
        ) else { return }

        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        do {
            let added = try appendCodexServer(into: folder.appendingPathComponent("config.toml"),
                                              executablePath: executablePath)
            if added {
                showAlert(.informational, "Added to Codex", "Restart Codex, then ask it about your pads.")
            } else {
                showAlert(.informational, "Already in Codex",
                          "Codex already has a \u{201C}coderpad\u{201D} server. "
                              + "Edit ~/.codex/config.toml by hand if its path changed.")
            }
        } catch {
            showAlert(.warning, "Couldn't update Codex", error.localizedDescription)
        }
    }

    // MARK: - JSON config (Claude Desktop)

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
    /// pre-pointing the panel there sends the user — and the written file — into the
    /// container instead of the actual client config (the whole reason the button looked
    /// like it did nothing). `getpwuid` returns the true home regardless of the sandbox.
    private static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
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
