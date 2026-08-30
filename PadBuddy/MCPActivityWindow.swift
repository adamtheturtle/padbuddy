//
//  MCPActivityWindow.swift
//  coderpad
//
//  The MCP activity log (#523) as its own window, opened from the MCP settings pane, rather
//  than an inline section. Shows when the headless `--mcp` server last ran and its recent
//  tool calls (names + ok/error only), polled from `MCPActivityLog` via `MCPActivityStore`.
//

import SwiftUI
import UniformTypeIdentifiers

/// The window's scene id, shared by the `Window` scene and the button that opens it.
enum MCPActivityWindowID {
    static let value = "mcp-activity"
}

struct MCPActivityView: View {
    @State private var activity = MCPActivityStore()
    @AppStorage(MCPActivityPresentation.detailsDefaultsKey) private var detailsVisible = false
    @State private var exportDocument: MCPActivityExportDocument?
    @State private var exportError: String?
    @AppStorage("mcpActivityFilterText") private var filterText = ""

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
                    Section {
                        Button {
                            do {
                                exportDocument = try MCPActivityExportDocument(
                                    entries: activity.entries, revealDetails: detailsVisible
                                )
                            } catch {
                                exportError = String(
                                    localized: "Could not prepare the activity export — \(error.localizedDescription)"
                                )
                            }
                        } label: {
                            Label("Export Activity for Support…", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let launch = activity.lastLaunch {
                        Section {
                            LabeledContent {
                                if detailsVisible {
                                    Text(launch.time, format: .relative(presentation: .named))
                                        .foregroundStyle(.secondary)
                                }
                            } label: {
                                Label(
                                    MCPActivityPresentation.launchLabel(
                                        launch, revealDetails: detailsVisible
                                    ),
                                    systemImage: "bolt.horizontal.circle"
                                )
                            }
                        } footer: {
                            Text(recordedFooter)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Recent tool calls") {
                        if filteredCalls.isEmpty, !boundedFilterText.isEmpty {
                            ContentUnavailableView.search(text: boundedFilterText)
                        } else {
                            ForEach(filteredCalls.prefix(100)) { call in
                                callRow(call)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
        .searchable(
            text: filterBinding,
            prompt: detailsVisible
                ? String(localized: "Filter by tool or account")
                : String(localized: "Show details to filter")
        )
        .onChange(of: filterText, initial: true) { _, value in
            let bounded = MCPActivityPresentation.boundedFilterText(value)
            if value != bounded {
                filterText = bounded
                return
            }
            if !detailsVisible, !value.isEmpty {
                filterText = ""
            }
        }
        .onChange(of: detailsVisible) { _, visible in
            if !visible {
                filterText = ""
            }
        }
        .task { await activity.poll() }
        .safeAreaInset(edge: .top) {
            if activity.retentionTrimFailed {
                Label(
                    "Activity retention could not be saved. The existing log was left unchanged.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: {
                if !$0 {
                    exportError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .fileExporter(
            isPresented: .init(
                get: { exportDocument != nil },
                set: {
                    if !$0 {
                        exportDocument = nil
                    }
                }
            ),
            document: exportDocument,
            contentType: .json,
            defaultFilename: "PadBuddy-MCP-Activity"
        ) { _ in
            exportDocument = nil
        }
    }

    private var recordedFooter: String {
        if !detailsVisible {
            return String(localized: "Activity details are hidden in MCP Server settings.")
        }
        #if os(macOS)
            return String(localized: """
            Recorded on this Mac. Tool names and times only, never pad or candidate content.
            """)
        #else
            return String(localized: """
            Recorded on this device. Tool names and times only, never pad or candidate content.
            """)
        #endif
    }

    private var filteredCalls: [MCPActivityEntry] {
        MCPActivityPresentation.filteredCalls(
            activity.recentCalls, query: boundedFilterText, revealDetails: detailsVisible
        )
    }

    private var boundedFilterText: String {
        MCPActivityPresentation.boundedFilterText(filterText)
    }

    private var filterBinding: Binding<String> {
        Binding(
            get: { boundedFilterText },
            set: { filterText = MCPActivityPresentation.boundedFilterText($0) }
        )
    }

    private func callRow(_ call: MCPActivityEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: call.succeeded == false ? "exclamationmark.circle" : "checkmark.circle")
                    .foregroundStyle(call.succeeded == false ? .orange : .green)
                    .accessibilityHidden(true)
                // Re-bounded at render (#1626): entries written before the
                // write-side caps (#1758) may carry oversized strings.
                Text(MCPActivityPresentation.toolLabel(call, revealDetails: detailsVisible))
                    .font(.system(.callout, design: .monospaced))
                Spacer()
                if let account = MCPActivityPresentation.accountLabel(
                    call, revealDetails: detailsVisible
                ) {
                    Text(account)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if detailsVisible {
                    Text(call.time, format: .relative(presentation: .numeric))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // The sanitized failure summary (#688): why the call errored, so the
            // user doesn't have to ask the assistant. Older log entries predate
            // the field and just show ok/error as before.
            if call.succeeded == false,
               let reason = MCPActivityPresentation.failureReason(
                   call, revealDetails: detailsVisible
               ), !reason.isEmpty {
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
        let tool = MCPActivityPresentation.toolLabel(call, revealDetails: detailsVisible)
        let status = call.succeeded == false ? String(localized: "error") : String(localized: "ok")
        if call.succeeded == false,
           let reason = MCPActivityPresentation.failureReason(
               call, revealDetails: detailsVisible
           ), !reason.isEmpty {
            return "\(tool), \(status), \(reason)"
        }
        return "\(tool), \(status)"
    }
}

/// A privacy-respecting support artifact: it uses the same details preference as the
/// activity UI, so hidden tool/account/failure fields cannot leak through Export.
struct MCPActivityExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        []
    }

    static var writableContentTypes: [UTType] {
        [.json]
    }

    private let data: Data

    init(entries: [MCPActivityEntry], revealDetails: Bool) throws {
        data = try Self.exportData(entries: entries, revealDetails: revealDetails)
    }

    static func exportData(
        entries: [MCPActivityEntry],
        revealDetails: Bool,
        encode: ([MCPActivityExportRecord]) throws -> Data = { try JSONEncoder.mcpActivityExport.encode($0) }
    ) throws -> Data {
        let records = entries.map { entry in
            MCPActivityExportRecord(entry: entry, revealDetails: revealDetails)
        }
        return try encode(records)
    }

    init(configuration _: ReadConfiguration) throws {
        throw CocoaError(.fileReadCorruptFile)
    }

    func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

nonisolated struct MCPActivityExportRecord: Encodable {
    let time: Date
    let kind: String
    let status: String?
    let tool: String?
    let account: String?
    let failureReason: String?

    init(entry: MCPActivityEntry, revealDetails: Bool) {
        time = entry.time
        kind = entry.kind.rawValue
        status = entry.succeeded.map { $0 ? "ok" : "error" }
        tool = revealDetails ? entry.tool : nil
        account = revealDetails ? entry.account : nil
        failureReason = revealDetails ? entry.failureReason : nil
    }
}

private extension JSONEncoder {
    nonisolated static var mcpActivityExport: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

#if os(macOS)
    extension PadBuddyApp {
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
