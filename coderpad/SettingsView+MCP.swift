//
//  SettingsView+MCP.swift
//  coderpad
//
//  The "MCP Server" settings pane: explains what the built-in Model Context Protocol
//  server is and why you'd use it, lets the user opt in, and, once enabled, gives a
//  copy-paste Terminal command per supported MCP client that writes the configuration
//  (#402). The app itself is the server (run with the --mcp flag, see MCPServer.swift),
//  so there is nothing to build or download and no API key to paste: the command points
//  the client at the app's own executable, which serves the selected account using the
//  key already in the Keychain.
//

import SwiftUI

extension SettingsView {
    var mcpTab: some View {
        Form {
            Section {
                Text("""
                The Model Context Protocol (MCP) lets AI assistants like Claude read your \
                CoderPad data (your pads, questions, quota, and organization) so you can \
                ask them about it in plain language. PadBuddy has the server built in and \
                serves your selected account, so there's nothing to install. It's \
                read-only: it never changes or deletes anything in CoderPad.
                """)
                .foregroundStyle(.secondary)
            } header: {
                Text("What it does")
            }

            Section {
                Toggle("Enable the MCP server", isOn: $mcpServerEnabled)
            }

            if mcpServerEnabled {
                mcpSetupSection
                mcpClaudeSection
                mcpCodexSection
            }
        }
        .formStyle(.grouped)
    }

    /// The shared flow: run the command for your assistant, then restart it.
    private var mcpSetupSection: some View {
        Section {
            Label("Copy the command for your assistant and run it in Terminal.", systemImage: "1.circle")
            Label("Restart the assistant. It uses the account selected in PadBuddy.",
                  systemImage: "2.circle")
        } header: {
            Text("Set it up")
        } footer: {
            Text("""
            The server reads the selected account's key straight from the Keychain, so \
            your API key is never written to a config file.
            """)
            .foregroundStyle(.secondary)
        }
    }

    /// Claude Desktop uses a JSON config; merge into it with python so any MCP servers
    /// already configured are preserved.
    private var mcpClaudeSection: some View {
        Section {
            Text("Adds PadBuddy to Claude Desktop, keeping any servers you already have, then takes effect after a restart.")
                .font(.callout)
                .foregroundStyle(.secondary)

            commandBlock(Self.claudeCommand)
            copyButton(Self.claudeCommand)
        } header: {
            Text("Claude Desktop")
        }
    }

    /// The Codex CLI uses a TOML config; append the entry (guarded so re-running is safe).
    private var mcpCodexSection: some View {
        Section {
            Text("Adds PadBuddy to the Codex CLI's config at ~/.codex/config.toml.")
                .font(.callout)
                .foregroundStyle(.secondary)

            commandBlock(Self.codexCommand)
            copyButton(Self.codexCommand)
        } header: {
            Text("Codex")
        }
    }

    /// A monospaced, selectable block showing a shell command.
    private func commandBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            Clipboard.copy(text)
        } label: {
            Label("Copy command", systemImage: "doc.on.doc")
        }
    }

    /// Terminal command that adds PadBuddy to Claude Desktop's JSON config, creating the
    /// file if needed and merging into any existing "mcpServers" so other servers survive.
    static var claudeCommand: String {
        """
        config="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
        mkdir -p "$(dirname "$config")"
        python3 - "$config" <<'PY'
        import json, os, sys
        path = sys.argv[1]
        config = {}
        if os.path.exists(path):
            try:
                with open(path) as file:
                    config = json.load(file)
            except ValueError:
                config = {}
        config.setdefault("mcpServers", {})["coderpad"] = {
            "command": "\(executablePath)",
            "args": ["--mcp"],
        }
        with open(path, "w") as file:
            json.dump(config, file, indent=2)
        print("Updated", path)
        PY
        """
    }

    /// Terminal command that appends the PadBuddy entry to the Codex CLI's TOML config.
    /// Guarded by grep so running it twice doesn't add a duplicate table.
    static var codexCommand: String {
        """
        mkdir -p "$HOME/.codex"
        grep -qsF '[mcp_servers.coderpad]' "$HOME/.codex/config.toml" || cat >> "$HOME/.codex/config.toml" <<'EOF'

        [mcp_servers.coderpad]
        command = "\(executablePath)"
        args = ["--mcp"]
        EOF
        """
    }

    /// The app's live executable path, so the command is correct wherever PadBuddy is
    /// installed; falls back to the conventional install location if it can't be read.
    private static var executablePath: String {
        Bundle.main.executablePath ?? "/Applications/PadBuddy.app/Contents/MacOS/PadBuddy"
    }
}
