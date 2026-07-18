//
//  MCPActivityWindow.swift
//  coderpad
//
//  The MCP activity log (#523) as its own window, opened from the MCP settings pane, rather
//  than an inline section. Shows when the headless `--mcp` server last ran and its recent
//  tool calls (names + ok/error only), polled from `MCPActivityLog` via `MCPActivityStore`.
//

import SwiftUI

/// The window's scene id, shared by the `Window` scene and the button that opens it.
enum MCPActivityWindowID {
    static let value = "mcp-activity"
}

struct MCPActivityView: View {
    @State private var activity = MCPActivityStore()

    var body: some View {
        Group {
            if activity.lastLaunch == nil, activity.recentCalls.isEmpty {
                ContentUnavailableView(
                    "No MCP activity yet",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("Connect an assistant to the server and its tool calls show up here.")
                )
            } else {
                Form {
                    if let launch = activity.lastLaunch {
                        Section {
                            LabeledContent {
                                Text(launch.time, format: .relative(presentation: .named))
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label(launchLabel(launch), systemImage: "bolt.horizontal.circle")
                            }
                        } footer: {
                            Text(recordedFooter)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Recent tool calls") {
                        ForEach(activity.recentCalls.prefix(100)) { call in
                            callRow(call)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        #if os(macOS)
            .frame(minWidth: 440, minHeight: 360)
        #endif
            .task { await activity.poll() }
    }

    private var recordedFooter: String {
        #if os(macOS)
            String(localized: "Recorded on this Mac. Tool names and times only, never pad or candidate content.")
        #else
            String(localized: "Recorded on this device. Tool names and times only, never pad or candidate content.")
        #endif
    }

    private func launchLabel(_ launch: MCPActivityEntry) -> String {
        if let account = MCPActivityLog.sanitizedField(launch.account, cap: 100) {
            return "Server last ran for \(account)"
        }
        return "Server last ran"
    }

    private func callRow(_ call: MCPActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: call.succeeded == false ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(call.succeeded == false ? .orange : .green)
                    .accessibilityHidden(true)
                // Re-bounded at render (#1626): entries written before the
                // write-side caps (#1758) may carry oversized strings.
                Text(MCPActivityLog.sanitizedField(call.tool, cap: 64) ?? "-")
                    .font(.system(.callout, design: .monospaced))
                Spacer()
                if let account = MCPActivityLog.sanitizedField(call.account, cap: 100) {
                    Text(account)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(call.time, format: .relative(presentation: .numeric))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The sanitized failure summary (#688): why the call errored, so the
            // user doesn't have to ask the assistant. Older log entries predate
            // the field and just show ok/error as before.
            if call.succeeded == false, let reason = call.failureReason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, 26)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(callAccessibilityLabel(call))
    }

    private func callAccessibilityLabel(_ call: MCPActivityEntry) -> String {
        let tool = MCPActivityLog.sanitizedField(call.tool, cap: 64) ?? "tool"
        let status = call.succeeded == false ? "error" : "ok"
        if call.succeeded == false, let reason = call.failureReason, !reason.isEmpty {
            return "\(tool), \(status), \(reason)"
        }
        return "\(tool), \(status)"
    }
}

#if os(macOS)
    extension CoderpadApp {
        /// The MCP activity log in its own window (#523), opened from the MCP settings pane.
        /// Defined here (not in the App's main scene file) so that file stays within its length
        /// budget; follows the system appearance. The standalone `Window` scene is macOS-only;
        /// on iPad the activity log opens as a sheet/inline instead.
        var mcpActivityScene: some Scene {
            Window("MCP Activity", id: MCPActivityWindowID.value) {
                MCPActivityView()
            }
            .defaultSize(width: 480, height: 460)
        }
    }
#endif

/// Opens the MCP activity log from the settings pane: the standalone window on macOS,
/// or a sheet on iOS, where that Window scene isn't registered and openWindow would
/// silently no-op (#835).
struct OpenMCPActivityButton: View {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow

        var body: some View {
            Button {
                openWindow(id: MCPActivityWindowID.value)
            } label: {
                Label("Open the activity window", systemImage: "list.bullet.rectangle")
            }
        }
    #else
        @State private var showingActivity = false

        var body: some View {
            Button {
                showingActivity = true
            } label: {
                Label("Show recent activity", systemImage: "list.bullet.rectangle")
            }
            .sheet(isPresented: $showingActivity) {
                NavigationStack {
                    MCPActivityView()
                        .navigationTitle("MCP Activity")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingActivity = false }
                            }
                        }
                }
            }
        }
    #endif
}
