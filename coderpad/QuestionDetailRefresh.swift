//
//  QuestionDetailRefresh.swift
//  coderpad
//

import SwiftUI

@Observable
final class QuestionDetailRefreshState {
    var lastSuccessfulRefresh: Date?
    var error: String?
}

struct QuestionDetailRefreshStatus: View {
    let state: QuestionDetailRefreshState

    var body: some View {
        if let date = state.lastSuccessfulRefresh {
            Text("Refreshed \(date.formatted(SharedDateStyles.longDateAndTime))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Question last refreshed "
                    + date.formatted(SharedDateStyles.longDateAndTime))
        }
        if let error = state.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

extension QuestionDetailView {
    func refreshQuestionDetail() async {
        do {
            let refreshed = try await client.getQuestion(id: question.id)
            guard !Task.isCancelled else { return }

            questionPublishGeneration &+= 1
            latestQuestion = refreshed
            questionRefresh.lastSuccessfulRefresh = Date()
            questionRefresh.error = nil
            AppRouter.questionUpdated(refreshed, account: owningAccountID)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }

            questionRefresh.error = String(error.localizedDescription.prefix(300))
        }
    }
}
