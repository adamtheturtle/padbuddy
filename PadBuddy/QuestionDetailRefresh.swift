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

nonisolated enum QuestionDetailRefreshResponse {
    static func matches(requestedID: Int, responseID: Int) -> Bool {
        responseID == requestedID
    }
}

struct QuestionDetailRefreshStatus: View {
    let state: QuestionDetailRefreshState

    var body: some View {
        if let error = state.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

extension QuestionDetailView {
    func refreshQuestionDetail() async {
        let requestedID = question.id
        do {
            let refreshed = try await client.getQuestion(id: requestedID)
            guard !Task.isCancelled else { return }
            guard QuestionDetailRefreshResponse.matches(requestedID: requestedID, responseID: refreshed.id) else {
                questionRefresh.error = String(localized: "Question refresh returned an unexpected question.")
                return
            }

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
