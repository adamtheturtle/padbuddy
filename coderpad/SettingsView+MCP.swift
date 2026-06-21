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
                serves your selected account, so there's nothing to install. By default \
                it's read-only: it never changes or deletes anything in CoderPad unless \
                you turn on changes below.
                """)
                .foregroundStyle(.secondary)
            } header: {
                Text("What it does")
            }

            Section {
                Toggle("Enable the MCP server", isOn: $mcpServerEnabled)
            }

            if mcpServerEnabled {
                mcpWritesSection
                mcpSetupSection
                mcpClaudeSection
                mcpClaudeCodeSection
                mcpCodexSection
                mcpVerifySection
            }
        }
        .formStyle(.grouped)
    }

    /// The separate, explicit write opt-in (#502). Distinct from enabling the server: read
    /// tools work without it; only with this on does the server advertise and allow the
    /// create/edit tools. Deletion is never offered over MCP.
    private var mcpWritesSection: some View {
        Section {
            Toggle("Allow the MCP server to make changes", isOn: $mcpServerAllowWrites)
        } footer: {
            Text("""
            Off by default. When on, the assistant can create and edit pads and questions \
            (never delete them). Changes take effect after you restart the assistant. Only \
            turn this on if you trust the assistant with your live interview content.
            """)
            .foregroundStyle(.secondary)
        }
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
            Text("""
            Adds PadBuddy to Claude Desktop, keeping any servers you already have. \
            Takes effect after a restart.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            commandBlock(Self.claudeCommand)
            copyButton(Self.claudeCommand)
        } header: {
            Text("Claude Desktop")
        }
    }

    /// Claude Code (the `claude` CLI) is a different product from Claude Desktop with its
    /// own MCP registry; it doesn't read claude_desktop_config.json, so it needs its own
    /// `claude mcp add` command (#501).
    private var mcpClaudeCodeSection: some View {
        Section {
            Text("""
            Claude Code is the `claude` command-line tool, separate from Claude Desktop. \
            It keeps its own list of MCP servers, so run this in Terminal.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            commandBlock(Self.claudeCodeCommand)
            copyButton(Self.claudeCodeCommand)
        } header: {
            Text("Claude Code")
        } footer: {
            Text("""
            `-s user` makes PadBuddy available in every project, not just the current \
            folder. Everything after `--` is passed to PadBuddy, so `--mcp` reaches the \
            app instead of being read as an option of `claude mcp add`.
            """)
            .foregroundStyle(.secondary)
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

    /// After running a command you almost always have to restart the assistant before it
    /// sees the server; this section says how to confirm it connected and where to look
    /// when it didn't (#501).
    private var mcpVerifySection: some View {
        Section {
            Text("""
            You usually have to fully restart the assistant before it picks up the server: \
            quit Claude Desktop with Command-Q and reopen it; start a new session in Claude \
            Code (or run `/mcp` to reconnect).
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            Text("""
            To confirm Claude Code connected, run `claude mcp list` or \
            `claude mcp get coderpad`. Claude Desktop writes logs to ~/Library/Logs/Claude/.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
        } header: {
            Text("Seeing it in your assistant")
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

    /// Terminal command that registers PadBuddy with Claude Code. `-s user` makes it
    /// available in every project; the `--` separator hands `--mcp` to PadBuddy rather
    /// than letting `claude mcp add` parse it.
    static var claudeCodeCommand: String {
        "claude mcp add coderpad -s user -- \(executablePath) --mcp"
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
