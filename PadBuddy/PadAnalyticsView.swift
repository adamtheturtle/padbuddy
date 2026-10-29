import SwiftUI

struct PadAnalyticsView: View {
    let client: CoderPadClient
    let identity: PadDetailLoadIdentity
    @State private var model = PadAnalyticsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Spacer()
                Button("Refresh Interview Insights", systemImage: "arrow.clockwise") {
                    Task { await model.load(client: client, identity: identity) }
                }
                .disabled(model.loading)
            }
            if model.identity == identity, let pad = model.pad {
                PadAnalyticsContent(pad: pad)
            } else if model.identity == identity, let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("Retry") { Task { await model.load(client: client, identity: identity) } }
            } else {
                ProgressView("Loading interview insights…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: identity) { await model.load(client: client, identity: identity) }
    }
}

struct PadAnalyticsContent: View {
    let pad: Pad

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DetailSection(title: "Interview Highlights", systemImage: "sparkles") {
                if let highlights = pad.interviewHighlights {
                    if highlights.isEmpty {
                        Text("No interview highlights.").foregroundStyle(.secondary)
                    } else {
                        MarkdownText(highlights)
                    }
                } else {
                    Text("Interview highlights are not available for this pad.").foregroundStyle(.secondary)
                }
            }
            DetailSection(title: "Interview Outline", systemImage: "list.bullet.indent") {
                if let outline = pad.interviewOutline {
                    StructuredContentView(outline)
                } else {
                    Text("An interview outline is not available for this pad.").foregroundStyle(.secondary)
                }
            }
            transcript
            reviews
        }
    }

    private var transcript: some View {
        DetailSection(title: "Transcript", systemImage: "text.bubble") {
            switch PadTranscriptAvailability(pad) {
            case .unavailable:
                Text("The transcript source is unavailable.").foregroundStyle(.secondary)
            case .notProvided:
                Text("A transcript is not available for this pad.").foregroundStyle(.secondary)
            case .empty:
                Text("The transcript is empty.").foregroundStyle(.secondary)
            case .available:
                let entries = pad.transcript ?? []
                ForEach(entries.indices.prefix(1000), id: \.self) { index in
                    TranscriptEntryRow(entry: entries[index])
                }
                if entries.count > 1000 {
                    Text("Some transcript entries are too numerous to display in full.").foregroundStyle(.orange)
                }
            }
        }
    }

    private var reviews: some View {
        DetailSection(title: "Owner Review Reports", systemImage: "doc.text.magnifyingglass") {
            if let reports = pad.reviewReports {
                if reports.isEmpty {
                    Text("No review reports.").foregroundStyle(.secondary)
                }
                ForEach(reports.indices.prefix(100), id: \.self) { index in
                    ReviewReportRow(report: reports[index])
                }
                if reports.count > 100 {
                    Text("Some review reports could not be displayed.").foregroundStyle(.orange)
                }
            } else {
                Text("Review reports are only available to the pad owner when provided by the service.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
