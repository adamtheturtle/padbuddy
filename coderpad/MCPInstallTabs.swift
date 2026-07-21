//
//  MCPInstallTabs.swift
//  coderpad
//
//  Per-client MCP setup as sub-tabs in the MCP settings pane: pick the assistant, get a
//  one-click "Add to <client>" button, with a fallback that shows the exact file and
//  snippet to paste. Backed by `MCPClientInstall`, which does the sandboxed config write.
//

import SwiftUI

struct MCPInstallTabs: View {
    let executablePath: String
    @State private var client: MCPClientInstall.Client = .claudeDesktop
    @State private var isManualInstructionsExpanded = false

    var body: some View {
        Picker("Assistant", selection: $client) {
            ForEach(MCPClientInstall.Client.allCases) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text("Adds PadBuddy to \(client.displayName). " + client.restartHint)
            .font(.callout)
            .foregroundStyle(.secondary)

        Button {
            Task { await MCPClientInstall.install(client, executablePath: executablePath) }
        } label: {
            Label("Add to \(client.displayName)", systemImage: "wand.and.stars")
        }

        if let verifyHint = client.verifyHint {
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
        let snippet = client.snippet(executablePath: executablePath)
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
    }
}
