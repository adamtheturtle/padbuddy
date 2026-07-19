//
//  NewPadFromQuestionCommands.swift
//  coderpad
//
//  File-menu "New Pad from Question" submenu (#534): the same one-click pad creation the
//  menu-bar extra offers, surfaced in the main-window menu too (it's also in the Cmd-K
//  command palette). Kept as its own `Commands` struct so the store observation it needs
//  stays out of the `App` body and only this submenu rebuilds when questions load.
//

import os
import SwiftUI

@MainActor
enum NewPadFromQuestionRunner {
    /// Account-namespaced keys of creates already in flight, so repeated menu or
    /// palette activations can't create several pads from the same question before
    /// the first create returns (#1250).
    private static var inFlight: Set<String> = []

    /// Creates a pad directly from `question` and opens it in the user's browser.
    /// On failure it falls back to the in-app create sheet seeded
    /// with the question, matching the app's other create-pad recovery paths.
    static func createAndOpen(question: Question, account: Account) {
        let key = "\(account.id.uuidString):\(question.id)"
        guard inFlight.insert(key).inserted else { return }

        let client = account.makeClient()
        let accountID = account.id
        let body = PadCreate.fromQuestion(question)
        Task { @MainActor in
            defer { inFlight.remove(key) }
            do {
                let pad = try await client.createPad(body)
                // Publish the created pad to the shared cache (Spotlight, widget,
                // Dock badge) and to every mounted list, so it doesn't stay
                // invisible in-app until the next full reload (#1251).
                PadsCacheStore.shared.insertPad(pad, account: accountID, via: client)
                AppRouter.padCreated(pad, account: accountID)
                // The canonical {base}/{id} fallback (#781): a response with a missing
                // or malformed url must not silently lose the just-created pad (#1004).
                BrowserSettings.openExternally(pad.webURL(fallbackBase: account.resolvedBaseURL))
            } catch {
                // The create can outlive its account: routing the fallback sheet at
                // an account removed mid-flight would present a create flow against
                // credentials the user just discarded, so log and drop it (#1252).
                guard AccountsStore.shared.accounts.contains(where: { $0.id == accountID }) else {
                    persistenceLogger.warning(
                        """
                        New Pad from Question failed and its account \
                        \(accountID.uuidString, privacy: .public) was removed mid-create; \
                        dropping the fallback: \(error.localizedDescription, privacy: .public)
                        """
                    )
                    return
                }

                AppNavigation.shared.routeNewPad(account: accountID.uuidString, seedQuestionID: question.id)
            }
        }
    }
}

struct NewPadFromQuestionCommands: Commands {
    /// Observed so the submenu tracks the active account set and its loaded
    /// questions, and disables itself while offline - mirroring the menu-bar extra.
    @State private var accounts = AccountsStore.shared
    @State private var questionsCache = QuestionsCacheStore.shared
    @State private var network = NetworkMonitor.shared

    /// At most this many questions are listed so the menu stays usable on a large org;
    /// favourites lead the list, so the most-used ones are always present.
    private let limit = 12

    /// One submenu row: a question paired with its owning account, so the merged
    /// "All Accounts" mode creates the pad against the question's own account
    /// rather than whichever account happens to be current (#1009). The id is
    /// account-namespaced because per-org question ids collide across accounts.
    private struct Row: Identifiable {
        let question: Question
        let account: Account
        var id: String {
            "\(account.id.uuidString):\(question.id)"
        }
    }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            let rows = orderedRows()
            if !rows.isEmpty {
                Menu("New Pad from Question") {
                    ForEach(rows.prefix(limit)) { row in
                        Button {
                            NewPadFromQuestionRunner.createAndOpen(question: row.question, account: row.account)
                        } label: {
                            // Starred questions lead the list and carry the star, so a
                            // frequently used question is the first one-click pad.
                            if isFavorite(row) {
                                Label(rowLabel(row), systemImage: "star.fill")
                            } else {
                                Text(rowLabel(row))
                            }
                        }
                        .disabled(row.account.isMock == false && row.account.apiKey.isEmpty)
                    }
                }
                .disabled(network.isOffline)
            }
        }
    }

    /// The accounts whose cached questions feed the submenu: every mergeable
    /// account in All Accounts mode (matching the menu-bar extra, #674), else just
    /// the current one (#1009).
    private var sourceAccounts: [Account] {
        if accounts.isMergedView { return accounts.mergeableAccounts }
        return [accounts.currentAccount].compactMap(\.self)
    }

    /// Every source account's cached questions, favourites (across all accounts)
    /// first - the same ordering the menu-bar extra's `questionsForMenu()` uses.
    private func orderedRows() -> [Row] {
        let rows = sourceAccounts.flatMap { account in
            questionsCache.cached(account.id).map { Row(question: $0, account: account) }
        }
        return rows.filter(isFavorite) + rows.filter { !isFavorite($0) }
    }

    private func isFavorite(_ row: Row) -> Bool {
        FavoriteQuestionsStore.shared.favorites(account: row.account.id).contains(row.question.id)
    }

    /// The row title, naming the owning account in merged mode so same-named
    /// questions from different orgs stay distinguishable (mirrors the menu-bar
    /// extra's `questionRowLabel`).
    private func rowLabel(_ row: Row) -> String {
        accounts.isMergedView ? "\(row.question.displayTitle) · \(row.account.name)" : row.question.displayTitle
    }
}
