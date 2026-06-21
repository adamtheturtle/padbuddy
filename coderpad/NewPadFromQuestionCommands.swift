//
//  NewPadFromQuestionCommands.swift
//  coderpad
//
//  File-menu "New Pad from Question" submenu (#534): the same one-click pad creation the
//  menu-bar extra offers, surfaced in the main-window menu too (it's also in the Cmd-K
//  command palette). Kept as its own `Commands` struct so the store observation it needs
//  stays out of the `App` body and only this submenu rebuilds when questions load.
//

import SwiftUI

struct NewPadFromQuestionCommands: Commands {
    /// Observed so the submenu tracks the current account and its loaded questions, and
    /// disables itself while offline — mirroring the menu-bar extra.
    @State private var accounts = AccountsStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State private var network = NetworkMonitor.shared

    /// At most this many questions are listed so the menu stays usable on a large org;
    /// favourites lead the list, so the most-used ones are always present.
    private let limit = 12

    var body: some Commands {
        CommandGroup(after: .newItem) {
            if let account = accounts.currentAccount {
                let questions = questionsCache.get(account.id)
                if !questions.isEmpty {
                    let favoriteIDs = Set(FavoriteQuestionsStore.shared.favorites(account: account.id))
                    let ordered = questions.filter { favoriteIDs.contains($0.id) }
                        + questions.filter { !favoriteIDs.contains($0.id) }
                    Menu("New Pad from Question") {
                        ForEach(ordered.prefix(limit)) { question in
                            Button {
                                InterviewTemplateRunner.createAndOpen(question: question, account: account)
                            } label: {
                                // Starred questions lead the list and carry the star, so a
                                // frequently used question is the first one-click pad.
                                if favoriteIDs.contains(question.id) {
                                    Label(question.displayTitle, systemImage: "star.fill")
                                } else {
                                    Text(question.displayTitle)
                                }
                            }
                        }
                    }
                    .disabled((account.isMock == false && account.apiKey.isEmpty) || network.isOffline)
                }
            }
        }
    }
}
