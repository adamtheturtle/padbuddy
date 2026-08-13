//
//  QuestionDetailPreviews.swift
//  coderpad
//

#if DEBUG
    import SwiftUI

    enum QuestionDetailPreviewLoadOutcome {
        case loaded(Question)
        case failed(String)
    }

    @MainActor
    func loadQuestionDetailPreview(using operation: () async throws -> Question) async throws
        -> QuestionDetailPreviewLoadOutcome {
        do {
            return .loaded(try await operation())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .failed("Could not load the question preview — \(error.localizedDescription)")
        }
    }

    private struct QuestionDetailFixturePreview: View {
        enum Section {
            case overview, materials
        }

        let questionID: Int
        let section: Section
        @State private var question: Question?
        @State private var loadError: String?
        @State private var reloadID = 0

        var body: some View {
            Group {
                if let question {
                    let detail = QuestionDetailView(
                        client: CoderPadClient.mock(key: "question-detail-preview"),
                        question: question
                    )
                    switch section {
                    case .overview: detail.overviewCard
                    case .materials: detail.materialsPane
                    }
                } else if let loadError {
                    ContentUnavailableView {
                        Label("Preview Failed", systemImage: "exclamationmark.triangle.fill")
                    } description: {
                        Text(verbatim: loadError)
                    } actions: {
                        Button("Try Again") { reloadID += 1 }
                    }
                } else {
                    ProgressView()
                }
            }
            .task(id: reloadID) {
                loadError = nil
                do {
                    let outcome = try await loadQuestionDetailPreview {
                        try await CoderPadClient.mock(key: "question-detail-preview").getQuestion(id: questionID)
                    }
                    guard !Task.isCancelled else { return }
                    switch outcome {
                    case let .loaded(question): self.question = question
                    case let .failed(message): loadError = message
                    }
                } catch is CancellationError {
                    return
                } catch {
                    assertionFailure("Preview loading only throws cancellation: \(error)")
                }
            }
        }
    }

    #Preview("Question Overview — Wide") {
        QuestionDetailFixturePreview(questionID: 101, section: .overview)
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
