//
//  QuestionDetailPreviews.swift
//  coderpad
//

#if DEBUG
    import SwiftUI

    private struct QuestionDetailFixturePreview: View {
        enum Section {
            case summary, materials
        }

        let questionID: Int
        let section: Section
        @State private var question: Question?

        var body: some View {
            Group {
                if let question {
                    let detail = QuestionDetailView(
                        client: CoderPadClient.mock(key: "question-detail-preview"),
                        question: question
                    )
                    switch section {
                    case .summary: detail.summaryCard
                    case .materials: detail.materialsPane
                    }
                } else {
                    ProgressView()
                }
            }
            .task {
                question = try? await CoderPadClient.mock(key: "question-detail-preview").getQuestion(id: questionID)
            }
        }
    }

    #Preview("Question Summary — Wide") {
        QuestionDetailFixturePreview(questionID: 101, section: .summary)
            .frame(width: 760)
            .padding()
    }

    #Preview("Question Materials — Narrow") {
        QuestionDetailFixturePreview(questionID: 101, section: .materials)
            .frame(width: 340)
            .padding()
    }

    #Preview("Question Materials — Empty") {
        QuestionDetailFixturePreview(questionID: 104, section: .materials)
            .frame(width: 340)
            .padding()
    }
#endif
