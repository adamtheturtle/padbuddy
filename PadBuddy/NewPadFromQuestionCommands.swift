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

    /// Palette actions can outlive the account snapshot used to build their labels.
    /// Resolve the UUID at invocation so re-keying/removal cannot use stale credentials
    /// or a stale server endpoint (#1979).
    static func createAndOpen(
        question: Question, accountID: UUID,
        clientIdentity: ClientTaskIdentity? = nil
    ) {
        guard let account = resolveAccount(id: accountID, in: AccountsStore.shared.accounts),
              clientIdentity == nil || account.makeClient().taskIdentity == clientIdentity else { return }

        createAndOpen(question: question, account: account)
    }

    nonisolated static func resolveAccount(id: UUID, in accounts: [Account]) -> Account? {
        accounts.first { $0.id == id }
    }

    /// Creates a pad directly from `question` and opens it in the user's browser.
    /// On failure it falls back to the in-app create sheet seeded
    /// with the question, matching the app's other create-pad recovery paths.
    static func createAndOpen(question: Question, account: Account) {
        guard isCurrent(account) else { return }

        let key = "\(account.id.uuidString):\(question.id)"
        guard inFlight.insert(key).inserted else { return }

        let client = account.makeClient()
        let accountID = account.id
        Task { @MainActor in
            defer { inFlight.remove(key) }
            do {
                // Menu/palette rows come from the local cache. Re-fetch immediately
                // before the write so edits, deletion, and revoked visibility cannot
                // create from an obsolete snapshot (#2043).
                let fetched = try await client.getQuestion(id: question.id)
                guard let fresh = NewPadFromQuestionValidation.accept(requestedID: question.id,
                                                                      fetched: fetched) else {
                    throw CoderPadError.decode(RecoveryMessages.unavailableQuestion)
                }
                guard isCurrent(account) else { return }

                QuestionsCacheStore.shared.updateQuestion(fresh, account: accountID, via: client)
                let pad = try await client.createPad(.fromQuestion(fresh))
                guard isCurrent(account) else { return }

                // Publish the created pad to the shared cache (Spotlight, widget,
                // Dock badge) and to every mounted list, so it doesn't stay
                // invisible in-app until the next full reload (#1251).
                PadsCacheStore.shared.insertPad(pad, account: accountID, via: client)
                AppRouter.padCreated(pad, account: accountID)
                // The canonical {base}/{id} fallback (#781): a response with a missing
                // or malformed url must not silently lose the just-created pad (#1004).
                guard let url = pad.webURL(fallbackBase: account.resolvedBaseURL) else {
                    throw CoderPadError.decode(RecoveryMessages.invalidCreatedPad)
                }

                BrowserSettings.openExternally(url)
            } catch {
                // A cancelled create is not a failure: teardown or navigation cancelling
                // this task must not push the user into an in-app create sheet they
                // never asked for, so drop it silently (#2041). Mirrors the widget
                // New Pad path in `AppDelegate+NewPad`.
                guard !Task.isCancelled, !(error is CancellationError) else { return }

                // A cached menu/palette row can outlive a deleted question. Remove
                // it and stop: opening a create sheet seeded with that missing ID
                // would merely defer the same failure (#1415).
                if CommandPaletteBuilder.isMissingRecord(error) {
                    QuestionsCacheStore.shared.removeQuestion(
                        id: question.id, account: accountID, via: client.taskIdentity
                    )
                    return
                }

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

                let message = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
                AppNavigation.shared.routeNewPad(account: accountID.uuidString,
                                                 seedQuestionID: question.id,
                                                 createError: message)
            }
        }
    }

    private static func isCurrent(_ account: Account) -> Bool {
        AccountsStore.shared.accounts.contains {
            $0.id == account.id && $0.makeClient().taskIdentity == account.makeClient().taskIdentity
        }
    }
}

enum NewPadFromQuestionValidation {
    static func accept(requestedID: Int, fetched: Question) -> Question? {
        fetched.id == requestedID ? fetched : nil
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
                        .disabled(!AppCreationAvailability.canCreate(
                            account: row.account,
                            isOffline: network.isOffline
                        ))
                    }
                }
            }
        }
    }

    /// The accounts whose cached questions feed the submenu: every mergeable
    /// account in All Accounts mode (matching the menu-bar extra, #674), else just
    /// the current one (#1009).
    private var sourceAccounts: [Account] {
        if accounts.isMergedView {
            return accounts.mergeableAccounts
        }
        return [accounts.currentAccount].compactMap(\.self)
    }

    /// Every source account's cached questions, favourites (across all accounts)
    /// first - the same ordering the menu-bar extra's `questionsForMenu()` uses.
    private func orderedRows() -> [Row] {
        // Each account's favourites are read once into a set, rather than per row:
        // `favorites(account:)` builds a fresh array every call, so the old two-pass
        // filter did 2N array allocations and 2N linear scans per menu render (#2232).
        // Duplicate account UUIDs must not trap the New Pad menu (#4614).
        let favoritesByAccount = Dictionary(sourceAccounts.map { account in
            (account.id, Set(FavoriteQuestionsStore.shared.favorites(account: account.id)))
        }, uniquingKeysWith: { first, _ in first })
        // Partitioned in one pass into favourites-first order, instead of filtering the
        // whole list twice and concatenating the results (#2231).
        var favorites: [Row] = []
        var others: [Row] = []
        var seen = Set<Row.ID>()
        for account in sourceAccounts {
            let accountFavorites = favoritesByAccount[account.id] ?? []
            for question in questionsCache.cached(account.id) {
                let row = Row(question: question, account: account)
                // Cache refreshes can briefly contain the same question twice. Keep
                // the first account-scoped row so ForEach identities stay unique;
                // the same numeric ID in another account remains a distinct row.
                guard seen.insert(row.id).inserted else { continue }

                if accountFavorites.contains(question.id) {
                    favorites.append(row)
                } else {
                    others.append(row)
                }
            }
            // Favourites lead the list, so once there are `limit` of them nothing
            // further can reach the menu and the rest of the scan is wasted.
            if favorites.count >= limit {
                break
            }
        }
        return favorites + others
    }

    private func isFavorite(_ row: Row) -> Bool {
        FavoriteQuestionsStore.shared.isFavorite(row.question.id, account: row.account.id)
    }

    /// The row title, naming the owning account in merged mode so same-named
    /// questions from different orgs stay distinguishable (mirrors the menu-bar
    /// extra's `questionRowLabel`).
    private func rowLabel(_ row: Row) -> String {
        accounts.isMergedView ? "\(row.question.displayTitle) · \(row.account.name)" : row.question.displayTitle
    }
}
