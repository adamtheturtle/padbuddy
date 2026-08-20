//
//  MCPInstallTabs.swift
//  coderpad
//
//  Per-client MCP setup as sub-tabs in the MCP settings pane: pick the assistant, get a
//  one-click "Add to <client>" button, with a fallback that shows the exact file and
//  snippet to paste. Backed by `MCPClientInstall`, which does the sandboxed config write.
//

#if os(macOS)
    import MCPClientInstall
    import SwiftUI

    struct MCPInstallTabs: View {
        let executablePath: String
        @State private var client: MCPDesktopClient = .claudeDesktop
        @State private var isManualInstructionsExpanded = false

        var body: some View {
            Picker("Assistant", selection: $client) {
                ForEach(MCPDesktopClient.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Adds PadBuddy to \(client.displayName). " + client.padBuddyRestartHint)
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { await PadBuddyMCPInstaller.install(client, executablePath: executablePath) }
            } label: {
                Label("Add to \(client.displayName)", systemImage: "wand.and.stars")
            }

            #if os(macOS)
                Button {
                    Task { await PadBuddyMCPInstaller.restorePreviousConfiguration(for: client) }
                } label: {
                    Label("Restore previous configuration", systemImage: "arrow.uturn.backward")
                }
                .help("Restore the backup saved before PadBuddy last changed this assistant's configuration.")
            #endif

            if let verifyHint = client.padBuddyVerifyHint {
                Text(LocalizedStringKey(verifyHint))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            DisclosureGroup(isExpanded: $isManualInstructionsExpanded) {
                manualInstructions
            } label: {
                Text("Prefer to edit the file yourself?")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isManualInstructionsExpanded.toggle()
                    }
                    .accessibilityAddTraits(.isButton)
            }
            .font(.callout)
        }

        /// Which file to edit and exactly what to put in it - no shell script.
        @ViewBuilder
        private var manualInstructions: some View {
            if let snippet = try? client.padBuddySnippet(executablePath: executablePath) {
                Text("Add the `padbuddy` server to this file - create it with the text below if it "
                    + "does not exist, otherwise add just the `padbuddy` block to what's already there:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(client.configPath)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(snippet)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        Color.platformTextBackground,
                        in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                    )
                Button {
                    Clipboard.copy(snippet)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            } else {
                Text("PadBuddy could not prepare manual setup instructions for this executable.")
                    .foregroundStyle(.secondary)
            }
        }
    }
#endif
