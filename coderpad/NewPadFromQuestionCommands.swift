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

@MainActor
enum NewPadFromQuestionRunner {
    /// Creates a pad directly from `question` and opens it, honoring the in-app/external
    /// browser preference. On failure it falls back to the in-app create sheet seeded
    /// with the question, matching the app's other create-pad recovery paths.
    static func createAndOpen(question: Question, account: Account) {
        let client = account.makeClient()
        let accountID = account.id
        let body = PadCreate.fromQuestion(question)
        Task { @MainActor in
            do {
                let pad = try await client.createPad(body)
                guard let url = pad.webURL else { return }

                AppActivator.bringToFront()
                if BrowserSettings.openLinksIn == .external {
                    BrowserSettings.openExternally(url)
                } else {
                    AppRouter.requestOpenPadInBrowser(url)
                }
            } catch {
                AppNavigation.shared.routeNewPad(account: accountID.uuidString, seedQuestionID: question.id)
            }
        }
    }
}

struct NewPadFromQuestionCommands: Commands {
    /// Observed so the submenu tracks the current account and its loaded questions, and
    /// disables itself while offline - mirroring the menu-bar extra.
    @State private var accounts = AccountsStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State private var network = NetworkMonitor.shared

    /// At most this many questions are listed so the menu stays usable on a large org;
    /// favourites lead the list, so the most-used ones are always present.
    private let limit = 12

    var body: some Commands {
        CommandGroup(after: .newItem) {
            if let account = accounts.currentAccount {
                let questions = questionsCache.cached(account.id)
                if !questions.isEmpty {
                    let favoriteIDs = Set(FavoriteQuestionsStore.shared.favorites(account: account.id))
                    let ordered = questions.filter { favoriteIDs.contains($0.id) }
                        + questions.filter { !favoriteIDs.contains($0.id) }
                    Menu("New Pad from Question") {
                        ForEach(ordered.prefix(limit)) { question in
                            Button {
                                NewPadFromQuestionRunner.createAndOpen(question: question, account: account)
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
