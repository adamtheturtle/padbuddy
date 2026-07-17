//
//  SettingsView+MCP.swift
//  coderpad
//
//  The "MCP Server" settings pane: explains what the built-in Model Context Protocol
//  server is and why you'd use it, lets the user opt in, and, once enabled, offers a
//  one-click "Add to <client>" button per supported MCP client as sub-tabs (#402, #501),
//  with a manual file fallback. The app itself is the server (run with --mcp, see
//  MCPServer.swift), so there's nothing to build or download and no API key to paste: the
//  config points the client at the app's own executable, which serves the selected account
//  using the key already in the Keychain.
//

import SwiftUI

extension SettingsView {
    var mcpTab: some View {
        Form {
            Section {
                Text("""
                The Model Context Protocol (MCP) lets AI assistants like Claude read your \
                CoderPad data (your pads, questions, quota, and organization) so you can \
                ask them about it in plain language.
                """)
                .foregroundStyle(.secondary)
            } header: {
                Text("What it does")
            }

            Section {
                Toggle("Enable the MCP server", isOn: $mcpServerEnabled)
            } footer: {
                Text("""
                When off, the server refuses to run, so assistants you've already added \
                lose access the next time they start.
                """)
                .foregroundStyle(.secondary)
            }

            if mcpServerEnabled {
                mcpWritesSection

                Section {
                    MCPInstallTabs(executablePath: Self.executablePath)
                } header: {
                    Text("Add to your assistant")
                } footer: {
                    Text("Your API key is never written to the file - the server reads it from "
                        + "the Keychain at runtime.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    OpenMCPActivityButton()
                }
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
            The server is read-only by default. When on, the assistant can also create and \
            edit pads and questions (never delete them). Changes take effect after you \
            restart the assistant. Only turn this on if you trust the assistant with your \
            live interview content.
            """)
            .foregroundStyle(.secondary)
        }
    }

    /// The app's live executable path, so the config is correct wherever PadBuddy is
    /// installed; falls back to the conventional install location if it can't be read.
    static var executablePath: String {
        Bundle.main.executablePath ?? "/Applications/PadBuddy.app/Contents/MacOS/PadBuddy"
    }
}
