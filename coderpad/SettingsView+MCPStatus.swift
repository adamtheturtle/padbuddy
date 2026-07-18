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
    /// Stored lines that failed to decode on the last load, so the pane can flag
    /// a damaged log instead of it silently reading as no MCP use (#1146).
    private(set) var unreadableLines = 0

    /// The most recent `launch` entry, surfaced as the "last ran" line.
    var lastLaunch: MCPActivityEntry? {
        entries.last { $0.kind == .launch }
    }

    /// Recent tool calls, newest first.
    var recentCalls: [MCPActivityEntry] {
        entries.filter { $0.kind == .call }.reversed()
    }

    /// The newest entry already announced to assistive tech, so each poll only
    /// announces genuinely new activity (#1627). Nil until the first load, which
    /// sets the baseline silently.
    @ObservationIgnored private var announcedLatestID: UUID?

    func refresh() {
        let diagnostics = MCPActivityLog.loadWithDiagnostics()
        entries = diagnostics.entries
        unreadableLines = diagnostics.unreadableLines
        MCPActivityLog.trimIfNeeded()

        // Screen-reader users can't see the "last ran"/call times tick over as
        // the poll updates them; announce fresh server activity as a status
        // change instead (#1627).
        let latest = entries.last?.id
        if let latest, announcedLatestID != nil, latest != announcedLatestID {
            AccessibilityNotification.Announcement(String(localized: "New MCP server activity")).post()
        }
        announcedLatestID = latest
    }

    /// Refresh now, then every few seconds until the enclosing `.task` is cancelled (the
    /// pane closed or the tab changed).
    func poll() async {
        while !Task.isCancelled {
            refresh()
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                // A cancelled sleep ends the loop immediately: spinning through
                // refresh/log reads until the next top-of-loop check would churn
                // disk during teardown (#1624).
                return
            }
        }
    }
}

extension SettingsView {
    /// The activity section: a header line saying whether/when the server last ran, then a
    /// short list of recent tool calls. Hidden entirely until there's something to show, so
    /// it doesn't add noise before the user has wired up a client.
    @ViewBuilder
    var mcpActivitySection: some View {
        if mcpActivity.lastLaunch != nil || !mcpActivity.recentCalls.isEmpty || mcpActivity.unreadableLines > 0 {
            Section {
                if let launch = mcpActivity.lastLaunch {
                    LabeledContent {
                        Text(launch.time, format: .relative(presentation: .named))
                            .foregroundStyle(.secondary)
                    } label: {
                        Label(launchLabel(launch), systemImage: "bolt.horizontal.circle")
                    }
                }

                if mcpActivity.unreadableLines > 0 {
                    // A damaged log must not silently read as "no MCP use" (#1146).
                    let count = mcpActivity.unreadableLines
                    Label(
                        "^[\(count) recorded entries](inflect: true) couldn't be read and were skipped.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }

                ForEach(mcpActivity.recentCalls.prefix(20)) { call in
                    mcpCallRow(call)
                }
            } header: {
                Text("Activity")
            } footer: {
                Text("Recorded on this Mac. Tool names and times only, never pad or "
                    + "candidate content. Entries are removed after 30 days.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func launchLabel(_ launch: MCPActivityEntry) -> String {
        if let account = MCPActivityLog.sanitizedField(launch.account, cap: 100) {
            return "Server last ran for \(account)"
        }
        return "Server last ran"
    }

    private func mcpCallRow(_ call: MCPActivityEntry) -> some View {
        // Log-sourced fields are re-bounded at render too (#1626): entries
        // written before the write-side caps (#1758) may carry oversized or
        // control-laden strings.
        let tool = MCPActivityLog.sanitizedField(call.tool, cap: 64)
        let account = MCPActivityLog.sanitizedField(call.account, cap: 100)
        return HStack(spacing: 10) {
            Image(systemName: call.succeeded == false ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(call.succeeded == false ? .orange : .green)
                .accessibilityHidden(true)
            Text(tool ?? "—")
                .font(.system(.callout, design: .monospaced))
            Spacer()
            if let account {
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
            "\(tool ?? "tool"), \(call.succeeded == false ? "error" : "ok")"
        )
    }
}
