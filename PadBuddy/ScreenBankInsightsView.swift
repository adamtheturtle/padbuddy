import SwiftUI

struct ScreenBankInsightsView: View {
    let insights: ScreenQuestionInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailSection(title: "Question Usage", systemImage: "chart.bar") {
                if let usage = insights.usage {
                    if let count = usage.viewCount {
                        LabeledContent("Views", value: String(count))
                    }
                    if let time = usage.lastViewTime {
                        LabeledContent("Last viewed", value: time)
                    }
                    if let duration = usage.averageAnswerDurationSeconds {
                        LabeledContent("Average answer duration in seconds", value: String(duration))
                    }
                    if let rate = usage.timeoutRate {
                        LabeledContent("Timeout rate", value: String(rate))
                    }
                    if let score = usage.averageScore {
                        LabeledContent("Average score", value: String(score))
                    }
                } else {
                    Text("Usage statistics are not available.").foregroundStyle(.secondary)
                }
            }
            frequencies("Frequent Answers", values: insights.frequentAnswers)
            frequencies("Test Case Success", values: insights.testcasesSuccess)
            DetailSection(title: "Score Distribution", systemImage: "chart.bar.xaxis") {
                if let scores = insights.scoresDistribution {
                    if let total = scores.totalCandidates {
                        LabeledContent("Total candidates", value: String(total))
                    }
                    let ranges = scores.distribution ?? []
                    if ranges.isEmpty {
                        Text("No statistics for this selection.").foregroundStyle(.secondary)
                    }
                    ForEach(ranges.indices.prefix(200), id: \.self) { index in
                        let range = ranges[index]
                        HStack {
                            Text(verbatim: range.scoreRange ?? "")
                            Spacer()
                            if let count = range.candidateCount {
                                Text(verbatim: String(count))
                            }
                        }
                    }
                    if ranges.count > 200 {
                        Text("Some insight items are too numerous to display.")
                    }
                } else {
                    Text("Score distribution is not available.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func frequencies(_ title: LocalizedStringKey, values: [ScreenQuestionRepartitionInsights]?) -> some View {
        DetailSection(title: title, systemImage: "chart.bar") {
            if let values {
                if values.isEmpty {
                    Text("No statistics for this selection.").foregroundStyle(.secondary)
                }
                ForEach(values.indices.prefix(200), id: \.self) { index in
                    let value = values[index]
                    Text(verbatim: value.label ?? "").textSelection(.enabled)
                    if let count = value.count {
                        LabeledContent("Count", value: String(count))
                    }
                    if let percentage = value.percentage {
                        LabeledContent("Percentage", value: String(percentage))
                    }
                    if let correct = value.correct {
                        LabeledContent("Correct") { Text(correct ? "Yes" : "No") }
                    }
                    Divider()
                }
                if values.count > 200 {
                    Text("Some insight items are too numerous to display.")
                }
            } else {
                Text("Statistics are not available.").foregroundStyle(.secondary)
            }
        }
    }
}
