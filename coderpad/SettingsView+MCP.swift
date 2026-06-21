//
//  SettingsView+MCP.swift
//  coderpad
//
//  The "MCP Server" settings pane: explains what the built-in Model Context Protocol
//  server is and why you'd use it, lets the user opt in, and, once enabled, shows the
//  ready-to-paste MCP-client configuration (#402). The app itself is the server (run
//  with the --mcp flag, see MCPServer.swift), so there is nothing to build or download
//  and no API key to paste: the config points an MCP client at the app's own executable,
//  which serves the currently selected account using the key already in the Keychain.
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
                mcpConfigSection
            }
        }
        .formStyle(.grouped)
    }

    /// Setup is two steps because the app is the server: point the client at the app's
    /// own executable, then restart the client. No build, download, or API key needed.
    private var mcpSetupSection: some View {
        Section {
            Label("""
            Add the configuration below to your MCP client. For Claude Desktop that's its \
            claude_desktop_config.json (Settings, Developer, Edit Config).
            """, systemImage: "1.circle")
            Label("Restart your MCP client. It will use the account selected in PadBuddy.",
                  systemImage: "2.circle")
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

    /// The copyable MCP-client config. Points at the app's own executable with the --mcp
    /// flag; no key is included because the server reads it from the Keychain at runtime.
    private var mcpConfigSection: some View {
        Section {
            Text(Self.mcpClientConfig)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button {
                Clipboard.copy(Self.mcpClientConfig)
            } label: {
                Label("Copy configuration", systemImage: "doc.on.doc")
            }
        } header: {
            Text("Configuration")
        }
    }

    /// The MCP-client config snippet, built around the app's live executable path so it's
    /// correct wherever PadBuddy is installed.
    static var mcpClientConfig: String {
        let executable = Bundle.main.executablePath ?? "/Applications/PadBuddy.app/Contents/MacOS/PadBuddy"
        return """
        {
          "mcpServers": {
            "coderpad": {
              "command": "\(executable)",
              "args": ["--mcp"]
            }
          }
        }
        """
    }
}
