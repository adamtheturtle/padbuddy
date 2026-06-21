//
//  SettingsView+MCP.swift
//  coderpad
//
//  The "MCP Server" settings pane: explains what the local Model Context Protocol
//  server is and why you'd use it, lets the user opt in, and, once enabled, shows
//  the ready-to-paste MCP-client configuration (#402). The server itself ships as a
//  separate package in the open-source project (#393), so this pane is the in-app
//  explanation and setup helper rather than a live process control.
//

import SwiftUI

extension SettingsView {
    var mcpTab: some View {
        Form {
            Section {
                Text("""
                The Model Context Protocol (MCP) lets AI assistants like Claude read your \
                CoderPad data (your pads, questions, quota, and organization) so you can \
                ask them about it in plain language. The server runs locally on your Mac \
                and is read-only: it never changes or deletes anything in CoderPad. It's \
                part of this app's open-source project and runs as a separate command; \
                enable it below to see the setup steps.
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

    /// Step-by-step setup, kept terse: the heavy lifting (building the server) lives in
    /// the project's README, linked here, since the binary isn't bundled with the app.
    private var mcpSetupSection: some View {
        Section {
            Label("""
            Clone the project and build the server with \
            “swift run --package-path CoderPadMCP coderpad-mcp”.
            """, systemImage: "1.circle")
            Label("""
            Add the configuration below to your MCP client (for Claude Desktop, that's \
            its claude_desktop_config.json), replacing the package path with where you \
            cloned the project.
            """, systemImage: "2.circle")
            Label("""
            Paste your CoderPad API key in place of the placeholder, then restart your \
            MCP client.
            """, systemImage: "3.circle")

            HStack(spacing: 16) {
                Link("Setup instructions", destination: CoderPadLinks.mcpSetup)
                Link("Get an API key", destination: CoderPadLinks.apiSettings)
            }
            .font(.callout)
        } header: {
            Text("Set it up")
        } footer: {
            Text("""
            Your API key is kept out of this panel on purpose. Paste it directly into \
            your MCP client's config so it isn't shown here.
            """)
            .foregroundStyle(.secondary)
        }
    }

    /// The copyable MCP-client config. The API key is left as a placeholder rather than
    /// filled from the saved account, so the key never appears in (or is copied out of)
    /// the Settings window, consistent with the Touch-ID reveal gate on stored keys.
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

    /// The MCP-client config snippet. Uses a placeholder for the API key and a sample
    /// package path the user replaces with their checkout.
    static var mcpClientConfig: String {
        """
        {
          "mcpServers": {
            "coderpad": {
              "command": "swift",
              "args": [
                "run",
                "--package-path",
                "/path/to/coderpad-macos/CoderPadMCP",
                "coderpad-mcp"
              ],
              "env": {
                "CODERPAD_API_KEY": "<YOUR_CODERPAD_API_KEY>"
              }
            }
          }
        }
        """
    }
}
