//
//  SettingsView+MCPStatus.swift
//  coderpad
//
//  The MCP status / activity area in the MCP Settings pane (#523): shows that a `--mcp`
//  server has actually run (last launch, the account it served) and a list of recent tool
//  calls, by tailing the small activity log the headless process writes
//  (`MCPActivityLog`). Read-only and privacy-light — tool names + ok/error only.
//

import SwiftUI

/// Loads and periodically refreshes the MCP activity log for display. The log changes
/// out-of-process (the headless server appends to it), so the view polls rather than
/// relying on in-process observation.
@MainActor
@Observable
final class MCPActivityStore {
    private(set) var entries: [MCPActivityEntry] = []

    /// The most recent `launch` entry, surfaced as the "last ran" line.
    var lastLaunch: MCPActivityEntry? {
        entries.last { $0.kind == .launch }
    }

    /// Recent tool calls, newest first.
    var recentCalls: [MCPActivityEntry] {
        entries.filter { $0.kind == .call }.reversed()
    }

    func refresh() {
        entries = MCPActivityLog.load()
        MCPActivityLog.trimIfNeeded()
    }

    /// Refresh now, then every few seconds until the enclosing `.task` is cancelled (the
    /// pane closed or the tab changed).
    func poll() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(3))
        }
    }
}

extension SettingsView {
    /// The activity section: a header line saying whether/when the server last ran, then a
    /// short list of recent tool calls. Hidden entirely until there's something to show, so
    /// it doesn't add noise before the user has wired up a client.
    @ViewBuilder
    var mcpActivitySection: some View {
        if mcpActivity.lastLaunch != nil || !mcpActivity.recentCalls.isEmpty {
            Section {
                if let launch = mcpActivity.lastLaunch {
                    LabeledContent {
                        Text(launch.time, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(launchLabel(launch), systemImage: "bolt.horizontal.circle")
                    }
                }

                ForEach(mcpActivity.recentCalls.prefix(20)) { call in
                    mcpCallRow(call)
                }
            } header: {
                Text("Activity")
            } footer: {
                Text("Recorded on this Mac. Tool names and times only, never pad or "
                    + "candidate content.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func launchLabel(_ launch: MCPActivityEntry) -> String {
        if let account = launch.account, !account.isEmpty {
            return "Server last ran for \(account)"
        }
        return "Server last ran"
    }

    private func mcpCallRow(_ call: MCPActivityEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: call.succeeded == false ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(call.succeeded == false ? .orange : .green)
                .accessibilityHidden(true)
            Text(call.tool ?? "—")
                .font(.system(.callout, design: .monospaced))
            Spacer()
            if let account = call.account, !account.isEmpty {
                Text(account)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(call.time, format: .relative(presentation: .numeric))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(call.tool ?? "tool"), \(call.succeeded == false ? "error" : "ok")"
        )
    }
}
