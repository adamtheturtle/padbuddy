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
    /// Several members below are internal rather than private because the JSON and
    /// TOML halves of the installer live in their own files, split out to keep each
    /// within the file- and type-body-length limits.
    enum JSONConfigError: LocalizedError {
        case incompatibleMCPServers
        case incompatiblePadBuddyServer

        var errorDescription: String? {
            switch self {
            case .incompatibleMCPServers:
                "The existing mcpServers value is not a JSON object. PadBuddy left the config unchanged."
            case .incompatiblePadBuddyServer:
                "The existing mcpServers.padbuddy value is not a compatible command object. "
                    + "PadBuddy left the config unchanged."
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
            case .claudeDesktop: "If it does not show up, check Claude Desktop's logs in ~/Library/Logs/Claude/."
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
            // A command the client can't run is worse than no entry: it replaces a
            // working one and fails silently at the client's next launch (#2531).
            guard isRunnableExecutable(executablePath) else {
                showAlert(.warning, "Could not update \(client.displayName)", String(localized: """
                PadBuddy could not find its own program file, so it cannot tell \(client.displayName) \
                where to find it. Move PadBuddy to your Applications folder and try again.
                """))
                return
            }
            guard let folder = grantFolderAccess(
                preferred: spec.preferred,
                fallback: spec.fallback,
                message: spec.message
            ) else { return }

            let accessing = folder.startAccessingSecurityScopedResource()
            guard accessing else {
                showAlert(.warning, "Could not update \(client.displayName)", String(localized: """
                macOS did not grant PadBuddy access to that folder. Choose the client's configuration \
                folder again and allow access when prompted.
                """))
                return
            }

            defer { folder.stopAccessingSecurityScopedResource() }

            let configFolder: URL
            do {
                configFolder = try configurationFolder(
                    granted: folder, preferred: spec.preferred, fallback: spec.fallback
                )
            } catch {
                showAlert(.warning, "Could not update \(client.displayName)", error.localizedDescription)
                return
            }

            // The panel accepts any directory, and the installer then appends the
            // client's filename to it — so picking the wrong folder created or
            // overwrote an unrelated config.toml / mcp.json / .claude.json without a
            // word (#2530). An unexpected folder that doesn't already hold that file
            // is confirmed first, naming the exact path.
            guard confirmFolderIfUnexpected(configFolder, spec: spec, client: client) else { return }

            let url = configFolder.appendingPathComponent(spec.fileName)
            // Refuse anything that isn't a plain file (or nothing at all): a symlink
            // would write outside the folder the user granted and the UI named, and a
            // directory or FIFO produces confusing — or blocking — behaviour (#2545,
            // #2546).
            if let reason = refusalReason(for: configPathKind(at: url), fileName: spec.fileName) {
                showAlert(.warning, "Could not update \(client.displayName)", reason)
                return
            }

            do {
                if spec.isTOML {
                    try await upsertCodexServer(into: url, client: client, executablePath: executablePath)
                } else {
                    try await mergeJSONServer(into: url, client: client, executablePath: executablePath)
                }
            } catch {
                showAlert(.warning, "Could not update \(client.displayName)", error.localizedDescription)
            }
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
            // Match whatever the file already uses, so a server update doesn't rewrite
            // every line ending in it (#2543).
            let newline = dominantLineEnding(of: text)
            switch scan.declaration {
            case .notDeclared:
                // Appending to a file Codex already can't parse would report success
                // while leaving the server just as unavailable (#2541).
                if let problem = codexConfigStructuralProblem(in: text) {
                    throw CodexConfigError(errorDescription: String(localized: """
                    config.toml is not valid TOML — \(problem). PadBuddy will not add to a file it cannot \
                    read, because Codex would still refuse to load it. Fix that line and try again.
                    """))
                }

                let appended = block.components(separatedBy: "\n").joined(separator: newline)
                let merged = text.isEmpty ? appended : text + newline + appended
                try await Task.detached(priority: .userInitiated) {
                    try writeConfig(Data(merged.utf8), to: url)
                    try verifyCodexConfig(at: url, executablePath: executablePath)
                }.value
                showAlert(.informational, "Added to \(client.displayName)", client.restartHint)

            case .table:
                guard confirmUpdate(client), let range = scan.tableLineRange else { return }

                var lines = scan.lines
                // Keep the table's other settings; only command and args are ours (#2536).
                let replacement = codexTableReplacement(
                    body: Array(lines[range]).map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 },
                    executablePath: executablePath
                )
                lines.replaceSubrange(range, with: replacement)
                let updated = lines
                    .map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
                    .joined(separator: newline)
                try await Task.detached(priority: .userInitiated) {
                    try writeConfig(Data(updated.utf8), to: url)
                    try verifyCodexConfig(at: url, executablePath: executablePath)
                }.value
                showAlert(.informational, "Updated \(client.displayName)", client.restartHint)

            case .other:
                // Appending a second [mcp_servers.padbuddy] table would redefine the key and
                // could make the whole config unparseable, so leave the file untouched.
                throw CodexConfigError(errorDescription:
                    "config.toml already declares the \u{201C}padbuddy\u{201D} server in a style "
                        + "PadBuddy cannot safely rewrite. Edit its command in config.toml yourself.")
            }
        }

        // MARK: - Access + alerts

        /// True when it's safe to proceed: the folder is the one PadBuddy suggested, it
        /// already contains the client's config, or the user confirmed creating it.
        @MainActor
        private static func confirmFolderIfUnexpected(_ folder: URL, spec: ConfigSpec, client: Client) -> Bool {
            let target = folder.appendingPathComponent(spec.fileName)
            if FileManager.default.fileExists(atPath: target.path) { return true }
            if let preferred = spec.preferred,
               preferred.standardizedFileURL.path == folder.standardizedFileURL.path { return true }

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = String(localized: "Create \(spec.fileName) here?")
            alert.informativeText = String(localized: """
            That folder does not look like \(client.displayName)'s configuration folder and has no \
            \(spec.fileName) in it yet. PadBuddy would create one at \(target.path).
            """)
            alert.addButton(withTitle: String(localized: "Create"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            return alert.runModal() == .alertFirstButtonReturn
        }

        /// Asks whether to overwrite an already-configured `padbuddy` server (e.g. its path changed).
        /// Returns true only if the user picks Update.
        @MainActor
        static func confirmUpdate(_ client: Client) -> Bool {
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
        static func showAlert(_ style: NSAlert.Style, _ title: String, _ message: String) {
            let alert = NSAlert()
            alert.alertStyle = style
            alert.messageText = title
            alert.informativeText = message
            alert.runModal()
        }
    #endif
}
