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
                            Text("Recorded on this Mac. Tool names and times only, never pad or "
                                + "candidate content.")
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
        .frame(minWidth: 440, minHeight: 360)
        .task { await activity.poll() }
    }

    private func launchLabel(_ launch: MCPActivityEntry) -> String {
        if let account = launch.account, !account.isEmpty {
            return "Server last ran for \(account)"
        }
        return "Server last ran"
    }

    private func callRow(_ call: MCPActivityEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: call.succeeded == false ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(call.succeeded == false ? .orange : .green)
                .accessibilityHidden(true)
            Text(call.tool ?? "-")
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
        .accessibilityLabel("\(call.tool ?? "tool"), \(call.succeeded == false ? "error" : "ok")")
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

/// Opens the MCP activity window from the settings pane.
struct OpenMCPActivityButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: MCPActivityWindowID.value)
        } label: {
            Label("Open the activity window", systemImage: "list.bullet.rectangle")
        }
    }
}
