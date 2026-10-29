import SwiftUI

struct TranscriptEntryRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if entry.kind == .systemMessage {
                    Label("System message", systemImage: "info.circle")
                } else {
                    Text(verbatim: entry.speakerName ?? String(localized: "Unknown speaker"))
                    if let role = entry.speakerRole {
                        Text(verbatim: role).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption.weight(.semibold))
            Text(verbatim: String(entry.text.prefix(64 * 1024))).textSelection(.enabled)
            if entry.text.count > 64 * 1024 {
                Text("This transcript entry is too large to display in full.").foregroundStyle(.orange)
            }
            LabeledRow(label: "Timestamp (milliseconds)", value: String(entry.timestamp))
                .font(.caption).foregroundStyle(.secondary)
            Divider()
        }
    }
}

struct ReviewReportRow: View {
    let report: ReviewReport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: report.title ?? String(localized: "Review report")).font(.headline)
            LabeledRow(label: "Status", value: report.status)
            if let error = report.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let summary = report.summary {
                MarkdownText(String(summary.prefix(64 * 1024)))
            }
            if let content = report.report {
                MarkdownText(String(content.prefix(64 * 1024)))
            }
            if (report.summary?.count ?? 0) > 64 * 1024 || (report.report?.count ?? 0) > 64 * 1024 {
                Text("Some review content is too large to display in full.").foregroundStyle(.orange)
            }
            if report.report == nil, ["pending", "processing", "running"].contains(report.status.lowercased()) {
                Text("This review report is still being generated.").foregroundStyle(.secondary)
            }
            if let date = report.createdAt {
                LabeledRow(label: "Created", value: date.formatted(SharedDateStyles.longDateAndTime))
            }
            if let date = report.updatedAt {
                LabeledRow(label: "Updated", value: date.formatted(SharedDateStyles.longDateAndTime))
            }
            Divider()
        }
    }
}
