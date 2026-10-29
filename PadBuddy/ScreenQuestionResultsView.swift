import SwiftUI

struct ScreenQuestionResultsView: View {
    let session: ScreenTestSession

    var body: some View {
        DetailSection(title: "Question Results", systemImage: "list.bullet.clipboard") {
            VStack(alignment: .leading, spacing: 12) {
                ScreenResultRowsView(rows: [ScreenResultRows.value(
                    String(localized: "Timer type"),
                    session.timerType
                )])
                if session.questionEntries.isEmpty {
                    Text("No per-question results were provided for this session.").foregroundStyle(.secondary)
                }
                ForEach(Array(session.questionEntries.prefix(200).indices), id: \.self) { index in
                    switch session.questionEntries[index] {
                    case let .summary(question):
                        DisclosureGroup {
                            Text("This entry provides an integer question summary.")
                            Text("Detailed submissions are not available.")
                            ScreenResultRowsView(rows: [ScreenResultRows.value(
                                String(localized: "Last activity (epoch milliseconds)"), question.lastActivityTime
                            )])
                        } label: { Text("Question \(question.id)") }

                    case let .detailed(question):
                        ScreenDetailedQuestionResultView(question: question)
                    }
                }
                if session.questionEntries.count > 200 {
                    Text("Only the first 200 question results are shown.").foregroundStyle(.secondary)
                }
                if session.omittedQuestionCount > 0 {
                    Label("Some question results could not be displayed.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

struct ScreenDetailedQuestionResultView: View {
    let question: ScreenDetailedQuestion

    var body: some View {
        DisclosureGroup {
            Text(verbatim: question.id.uuidString).font(.caption).textSelection(.enabled)
            if let type = question.type {
                Text(verbatim: type).font(.caption).foregroundStyle(.secondary)
            }
            ScreenResultRowsView(rows: ScreenResultRows.rows(question))
        } label: { Text(verbatim: question.title ?? question.id.uuidString) }
    }
}

struct ScreenResultRowsView: View {
    let rows: [ScreenResultRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("No entries").foregroundStyle(.secondary)
            }
            ForEach(rows.indices, id: \.self) { index in
                switch rows[index] {
                case let .value(label, value):
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: label).font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: String(value.prefix(65536))).textSelection(.enabled)
                        if value.count > 65536 {
                            Text("Long content is truncated to 65536 characters.").font(.caption)
                        }
                    }

                case let .group(label, children):
                    DisclosureGroup { AnyView(Self(rows: children)) } label: { Text(verbatim: label) }
                }
            }
        }
    }
}
