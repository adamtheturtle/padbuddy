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

nonisolated enum MCPActivityPresentation {
    static let detailsDefaultsKey = "mcpActivityDetailsVisible"

    static func launchLabel(_ launch: MCPActivityEntry, revealDetails: Bool) -> String {
        guard revealDetails,
              let account = MCPActivityLog.sanitizedField(launch.account, cap: 100) else {
            return String(localized: "MCP server ran")
        }

        return String(localized: "Server ran for \(account)")
    }

    static func toolLabel(_ call: MCPActivityEntry, revealDetails: Bool) -> String {
        guard revealDetails else { return String(localized: "MCP tool call") }

        return MCPActivityLog.sanitizedField(call.tool, cap: 64) ?? String(localized: "Unknown tool")
    }

    static func accountLabel(_ call: MCPActivityEntry, revealDetails: Bool) -> String? {
        revealDetails ? MCPActivityLog.sanitizedField(call.account, cap: 100) : nil
    }

    static func failureReason(_ call: MCPActivityEntry, revealDetails: Bool) -> String? {
        revealDetails ? call.failureReason : nil
    }
}

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
    /// When the log was last read successfully, and whether the most recent attempt
    /// failed.
    ///
    /// The poll swallowed every failure and kept rendering the last good `entries`
    /// forever, so a shared container that became unreachable left the pane showing
    /// old activity as if it were current, with nothing to indicate otherwise
    /// (#2554). The view uses these to say the list is stale.
    private(set) var lastLoaded: Date?
    private(set) var isStale = false

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
        guard let diagnostics = MCPActivityLog.loadWithDiagnosticsIfReadable() else {
            // The log couldn't be read at all — no shared container, or the lock
            // couldn't be taken within its bounded wait. Keep showing what we have,
            // but stop presenting it as current.
            isStale = true
            return
        }

        entries = diagnostics.entries
        unreadableLines = diagnostics.unreadableLines
        lastLoaded = Date()
        isStale = false
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
        if mcpActivity.lastLaunch != nil || !mcpActivity.recentCalls.isEmpty
            || mcpActivity.unreadableLines > 0 || mcpActivity.isStale {
            Section {
                if let launch = mcpActivity.lastLaunch {
                    LabeledContent {
                        if mcpActivityDetailsVisible {
                            Text(launch.time, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        }
                    } label: {
                        Label(
                            MCPActivityPresentation.launchLabel(
                                launch, revealDetails: mcpActivityDetailsVisible
                            ),
                            systemImage: "bolt.horizontal.circle"
                        )
                    }
                }

                if mcpActivity.isStale {
                    // The log stopped being readable, so what's listed below is a
                    // snapshot, not live activity. Say so rather than letting old
                    // entries keep reading as current (#2554).
                    Label {
                        if mcpActivityDetailsVisible, let lastLoaded = mcpActivity.lastLoaded {
                            let age = Text(lastLoaded, format: .relative(presentation: .named))
                            Text("Activity couldn't be refreshed. Showing what was read \(age).")
                        } else {
                            Text("Activity couldn't be read.")
                        }
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark")
                    }
                    .foregroundStyle(.orange)
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
                Text(mcpActivityDetailsVisible
                    ? "Recorded on this Mac. Tool names and times only, never pad or candidate content."
                    : "Activity details are hidden. Entries are removed after 30 days.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func mcpCallRow(_ call: MCPActivityEntry) -> some View {
        // Log-sourced fields are re-bounded at render too (#1626): entries
        // written before the write-side caps (#1758) may carry oversized or
        // control-laden strings.
        let tool = MCPActivityPresentation.toolLabel(
            call, revealDetails: mcpActivityDetailsVisible
        )
        let account = MCPActivityPresentation.accountLabel(
            call, revealDetails: mcpActivityDetailsVisible
        )
        return HStack(spacing: 10) {
            Image(systemName: call.succeeded == false ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(call.succeeded == false ? .orange : .green)
                .accessibilityHidden(true)
            Text(tool)
                .font(.system(.callout, design: .monospaced))
            Spacer()
            if let account {
                Text(account)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if mcpActivityDetailsVisible {
                Text(call.time, format: .relative(presentation: .numeric))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(tool), \(call.succeeded == false ? "error" : "ok")"
        )
    }
}
