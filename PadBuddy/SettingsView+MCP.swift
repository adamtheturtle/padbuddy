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

#if os(macOS)
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
                    Toggle("Enable the MCP server", isOn: mcpServerEnabledBinding)
                } footer: {
                    Text("""
                    When off, the server refuses to run, so assistants you have already added \
                    lose access the next time they start.
                    """)
                    .foregroundStyle(.secondary)
                }

                if mcpServerEnabled {
                    Section("Server health") {
                        mcpHealthRow
                        Button("Test Again") { Task { await testMCPHealth() } }
                            .disabled(mcpHealthStatus == .checking)
                    }

                    mcpWritesSection

                    Section {
                        // The conventional-path fallback can point at nothing (the app
                        // moved or was renamed); say so instead of handing the user a
                        // config that silently fails (#1623).
                        if !FileManager.default.isExecutableFile(atPath: Self.executablePath) {
                            Label(
                                "The PadBuddy executable could not be found at the path below. "
                                    + "Move PadBuddy to /Applications and reopen Settings.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .foregroundStyle(.orange)
                        }
                        MCPInstallTabs(executablePath: Self.executablePath)
                    } header: {
                        Text("Add to your assistant")
                    } footer: {
                        Text("Your API key is never written to the file - the server reads it from "
                            + "the Keychain at runtime.")
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        Toggle("Show activity details", isOn: $mcpActivityDetailsVisible)
                        OpenMCPActivityButton()
                        Button("Clear Activity History", role: .destructive) {
                            showClearMCPActivityConfirmation = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { loadMCPWritePermissions() }
            .task(id: mcpServerEnabled) {
                if mcpServerEnabled {
                    await testMCPHealth()
                } else {
                    mcpHealthStatus = .idle
                }
            }
            .confirmationDialog(
                pendingMCPServerEnabled == true ? "Enable the MCP server?" : "Disable the MCP server?",
                isPresented: Binding(
                    get: { pendingMCPServerEnabled != nil },
                    set: {
                        if !$0 {
                            pendingMCPServerEnabled = nil
                        }
                    }
                ),
                titleVisibility: .visible
            ) {
                Button(pendingMCPServerEnabled == true ? "Enable MCP Server" : "Disable MCP Server") {
                    confirmMCPServerPreferenceChange()
                }
                Button("Cancel", role: .cancel) { pendingMCPServerEnabled = nil }
            } message: {
                if pendingMCPServerEnabled == true {
                    Text("Assistants you have configured can read every usable account after you restart them.")
                } else {
                    Text("Assistants you have configured will lose CoderPad access after you restart them.")
                }
            }
            .confirmationDialog(
                "Clear all MCP activity history?",
                isPresented: $showClearMCPActivityConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Activity History", role: .destructive) {
                    MCPActivityLog.clear()
                    mcpActivity.refresh()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the recorded tool names, account labels, statuses, and times from this Mac.")
            }
        }

        private var mcpServerEnabledBinding: Binding<Bool> {
            Binding(
                get: { mcpServerEnabled },
                set: { requested in
                    guard requested != mcpServerEnabled else { return }

                    pendingMCPServerEnabled = requested
                }
            )
        }

        private func confirmMCPServerPreferenceChange() {
            guard let requested = pendingMCPServerEnabled else { return }

            let values = MCPServerPreferenceChange(enabled: requested).confirmed(
                allowWrites: !mcpWritableAccountIDs.isEmpty
            )
            mcpServerEnabled = values.enabled
            if !values.allowWrites {
                mcpWritableAccountIDs.removeAll()
                saveMCPWritePermissions()
            }
            pendingMCPServerEnabled = nil
        }

        @ViewBuilder
        private var mcpHealthRow: some View {
            switch mcpHealthStatus {
            case .idle, .checking:
                LabeledContent("Starting the same check your assistant uses…") {
                    ProgressView().controlSize(.small)
                }

            case .usable:
                Label("The MCP server can launch and read a usable account.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case let .unusable(message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Copy Diagnostic") {
                        Clipboard.copy(Self.mcpHealthDiagnostic(message: message))
                    }
                }
            }
        }

        private func testMCPHealth() async {
            mcpHealthStatus = .checking
            let result = await MCPHealthCheck.run(executablePath: Self.executablePath)
            guard !Task.isCancelled, mcpServerEnabled else { return }

            mcpHealthStatus = result
        }

        /// The separate, explicit write opt-in (#502). Distinct from enabling the server: read
        /// tools work without it; only with this on does the server advertise and allow the
        /// create/edit tools. Deletion is never offered over MCP.
        private var mcpWritesSection: some View {
            Section {
                ForEach(store.accounts.filter { !$0.isMock }) { account in
                    Toggle(account.name, isOn: mcpWriteBinding(for: account.id))
                        .accessibilityLabel(Text(String(localized: "Allow MCP write access for \(account.name)",
                                                        table: "MCPPermissions")))
                        .help(String(localized: "Allows MCP tools to create and edit content in this account.",
                                     table: "MCPPermissions"))
                }
            } footer: {
                Text("""
                Every account is read-only by default. Enabled accounts allow the assistant to \
                create and edit pads and questions (never delete them). Restart the assistant \
                after changing access.
                """)
                .foregroundStyle(.secondary)
            }
        }

        private func mcpWriteBinding(for id: UUID) -> Binding<Bool> {
            Binding(
                get: { mcpWritableAccountIDs.contains(id) },
                set: { enabled in
                    if enabled {
                        mcpWritableAccountIDs.insert(id)
                    } else {
                        mcpWritableAccountIDs.remove(id)
                    }
                    saveMCPWritePermissions()
                }
            )
        }

        private func loadMCPWritePermissions() {
            mcpWritableAccountIDs = Set(
                (UserDefaults.standard.stringArray(forKey: MCPServer.writableAccountIDsDefaultsKey) ?? [])
                    .compactMap(UUID.init(uuidString:))
            )
        }

        private func saveMCPWritePermissions() {
            UserDefaults.standard.set(
                mcpWritableAccountIDs.map(\.uuidString).sorted(),
                forKey: MCPServer.writableAccountIDsDefaultsKey
            )
        }

        /// The app's live executable path, so the config is correct wherever PadBuddy is
        /// installed; falls back to the conventional install location if it can't be read.
        static var executablePath: String {
            Bundle.main.executablePath ?? "/Applications/PadBuddy.app/Contents/MacOS/PadBuddy"
        }

        static func mcpHealthDiagnostic(message: String) -> String {
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            return """
            PadBuddy MCP health diagnostic
            Version: \(version) (\(build))
            Platform: \(ProcessInfo.processInfo.operatingSystemVersionString)
            Executable: \(executablePath)
            Result: \(message)
            """
        }
    }
#endif
