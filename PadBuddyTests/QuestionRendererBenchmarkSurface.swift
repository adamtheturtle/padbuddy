#if os(macOS)
    import AppKit
    import FastList
    @testable import PadBuddy
    import SwiftUI

    @Observable
    final class QuestionBenchmarkState {
        var selection: Set<String> = []
        var favorites: Set<String> = []
    }

    struct QuestionBenchmarkRow: Identifiable {
        let id: String
        let question: Question
        let account: RowAccount?
        let presentation: QuestionRowPresentation

        @MainActor static func fixtures(merged: Bool) throws -> [Self] {
            let data = try JSONSerialization.data(withJSONObject: (1 ... 5000).map { index in
                ["id": index, "title": "Question \(index): design a reliable distributed scheduling service",
                 "language": index.isMultiple(of: 2) ? "python3" : "typescript",
                 "type": "live", "is_draft": index.isMultiple(of: 7)] as [String: Any]
            })
            let questions = try CoderPadClient.decoder.decode([Question].self, from: data)
            let accounts = (0 ..< 5).map { RowAccount(Account(name: "Organization \($0)", apiKey: "")) }
            return questions.map { question in
                let account = merged ? accounts[question.id % accounts.count] : nil
                return Self(id: "\(question.id % (merged ? accounts.count : 1)):\(question.id)",
                            question: question, account: account,
                            presentation: QuestionRowPresentation(question: question, account: account))
            }
        }
    }

    struct QuestionBenchmarkSurface: View {
        let native: Bool
        let rows: [QuestionBenchmarkRow]
        @Bindable var state: QuestionBenchmarkState

        var body: some View {
            let favorites = state.favorites
            if native {
                MacQuestionTable(
                    items: rows, selection: $state.selection, reloadID: favorites,
                    scrollToID: nil, onScrolledToID: {}, presentation: \.presentation,
                    rowAccount: \.account, isFavorite: { favorites.contains($0.id) },
                    toggleFavorite: { toggle($0.id) }, onDoubleClick: { _ in }, onReturn: { _ in },
                    leadingActions: { _ in [] }, trailingActions: { _ in [] },
                    pasteboardItem: { _ in nil }, menuItems: { _ in [] }, onTopRowChange: { _ in }
                )
            } else {
                FastList(rows, selection: $state.selection) { row in
                    QuestionRowHostableContent(
                        question: row.question, presentation: row.presentation, rowAccount: row.account,
                        isFavorite: favorites.contains(row.id), onToggleFavorite: { toggle(row.id) }
                    )
                }
            }
        }

        private func toggle(_ id: String) {
            if !state.favorites.insert(id).inserted {
                state.favorites.remove(id)
            }
        }
    }
#endif
