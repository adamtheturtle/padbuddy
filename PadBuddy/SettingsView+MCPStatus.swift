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

    static func filteredCalls(_ calls: [MCPActivityEntry], query: String, revealDetails: Bool) -> [MCPActivityEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard revealDetails, !query.isEmpty else { return calls }

        return calls.filter { call in
            call.tool?.localizedCaseInsensitiveContains(query) == true
                || call.account?.localizedCaseInsensitiveContains(query) == true
        }
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
    /// True when the most recent poll read the log but could not atomically apply
    /// its entry-count/privacy retention rewrite.
    private(set) var retentionTrimFailed = false

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
            // couldn't be taken within its bounded wait. Keep showing what we have,
            // could not be taken within its bounded wait. Keep showing what we have,
            // but stop presenting it as current.
            isStale = true
            return
        }

        entries = diagnostics.entries
        unreadableLines = diagnostics.unreadableLines
        lastLoaded = Date()
        isStale = false
        retentionTrimFailed = !MCPActivityLog.trimIfNeeded()

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
