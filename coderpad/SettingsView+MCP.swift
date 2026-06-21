//
//  SettingsView+MCP.swift
//  coderpad
//
//  The "MCP Server" settings pane: explains what the built-in Model Context Protocol
//  server is and why you'd use it, lets the user opt in, and, once enabled, shows the
//  ready-to-paste configuration for each supported MCP client (#402). The app itself is
//  the server (run with the --mcp flag, see MCPServer.swift), so there is nothing to
//  build or download and no API key to paste: the config points the client at the app's
//  own executable, which serves the selected account using the key already in the
//  Keychain.
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

    /// The shared setup flow: pick a client below, paste its configuration, restart it.
    private var mcpSetupSection: some View {
        Section {
            Label("Find your assistant below and copy its configuration.", systemImage: "1.circle")
            Label("""
            Paste it into that assistant's MCP configuration, then restart the assistant. \
            It uses the account selected in PadBuddy.
            """, systemImage: "2.circle")
        } header: {
            Text("Set it up")
        } footer: {
            Text("""
            The server reads the selected account's key straight from the Keychain, so \
            your API key never appears in the configuration.
            """)
            .foregroundStyle(.secondary)
        }
    }

    /// Claude Desktop uses a JSON config. The easiest way to open it is the built-in
    /// Edit Config button, which creates and reveals the file for you.
    private var mcpClaudeSection: some View {
        Section {
            Text("""
            In Claude Desktop, open Settings (⌘,), select the Developer tab, \
            and click Edit Config. That opens claude_desktop_config.json (in \
            ~/Library/Application Support/Claude/). Paste the JSON below, merging it in if \
            the file already has an "mcpServers" entry.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            configBlock(Self.claudeConfig)
            copyButton(Self.claudeConfig)
        } header: {
            Text("Claude Desktop")
        }
    }

    /// The Codex CLI uses a TOML config at a fixed path, so just point the user there.
    private var mcpCodexSection: some View {
        Section {
            Text("""
            For the Codex CLI, open ~/.codex/config.toml (create it if it doesn't exist) \
            and add the entry below.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)

            configBlock(Self.codexConfig)
            copyButton(Self.codexConfig)
        } header: {
            Text("Codex")
        }
    }

    /// A monospaced, selectable block showing a configuration snippet.
    private func configBlock(_ text: String) -> some View {
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
            Label("Copy configuration", systemImage: "doc.on.doc")
        }
    }

    /// Claude Desktop's JSON configuration. Points at the app's live executable path with
    /// the --mcp flag; no key, since the server reads it from the Keychain at runtime.
    static var claudeConfig: String {
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

    /// The Codex CLI's TOML configuration, equivalent to ``claudeConfig``.
    static var codexConfig: String {
        """
        [mcp_servers.coderpad]
        command = "\(executablePath)"
        args = ["--mcp"]
        """
    }

    /// The app's live executable path, so the config is correct wherever PadBuddy is
    /// installed; falls back to the conventional install location if it can't be read.
    private static var executablePath: String {
        Bundle.main.executablePath ?? "/Applications/PadBuddy.app/Contents/MacOS/PadBuddy"
    }
}
