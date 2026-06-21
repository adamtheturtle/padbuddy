//
//  MCPClientInstall.swift
//  coderpad
//
//  One-click "Add to Claude Desktop" for the MCP settings pane (#501): instead of copying
//  a Terminal command, write the PadBuddy server entry straight into Claude Desktop's JSON
//  config, merging with any servers already there.
//
//  The app is sandboxed, so it can't reach ~/Library/Application Support/Claude on its own.
//  The user grants access to that folder once through an open panel (the URL it returns is
//  security-scoped); we read, merge, and write within that scope. This is a one-time setup
//  action, so we don't persist a bookmark — a fresh grant per use keeps it simple and needs
//  no extra entitlement.
//

import AppKit

enum MCPClientInstall {
    /// Adds (or updates) the PadBuddy entry in Claude Desktop's config, preserving any
    /// other MCP servers, and reports the outcome with an alert. `executablePath` is the
    /// running app's binary, so the config points at wherever PadBuddy is installed.
    @MainActor
    static func addToClaudeDesktop(executablePath: String) {
        // Returns nil if the user cancels the access prompt.
        guard let folder = grantClaudeFolderAccess() else { return }

        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let configURL = folder.appendingPathComponent("claude_desktop_config.json")
        do {
            var root = try existingConfig(at: configURL)
            var servers = root["mcpServers"] as? [String: Any] ?? [:]
            servers["coderpad"] = ["command": executablePath, "args": ["--mcp"]]
            root["mcpServers"] = servers

            let data = try JSONSerialization.data(
                withJSONObject: root,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: configURL, options: .atomic)
            showAlert(
                style: .informational,
                title: "Added to Claude Desktop",
                message: "Quit Claude Desktop with Command-Q and reopen it, then ask it about your pads."
            )
        } catch {
            showAlert(
                style: .warning,
                title: "Couldn't update Claude Desktop",
                message: error.localizedDescription
            )
        }
    }

    /// Reads and parses the existing config, returning an empty object when the file is
    /// absent or empty. A malformed file throws so we don't silently clobber it.
    private static func existingConfig(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        return object
    }

    /// Prompts for access to the Claude config folder, pre-pointed at its standard location
    /// so the user usually just confirms. Returns nil if they cancel.
    @MainActor
    private static func grantClaudeFolderAccess() -> URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let claude = support?.appendingPathComponent("Claude", isDirectory: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.message = "Select Claude Desktop's \u{201C}Claude\u{201D} folder so PadBuddy can add itself "
            + "to its configuration."
        if let claude, FileManager.default.fileExists(atPath: claude.path) {
            panel.directoryURL = claude
        } else {
            panel.directoryURL = support
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private static func showAlert(style: NSAlert.Style, title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
