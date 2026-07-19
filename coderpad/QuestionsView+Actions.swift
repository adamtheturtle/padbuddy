//
//  QuestionsView+Actions.swift
//  coderpad
//
//  Split from QuestionsView+List.swift to keep it within the lint length limit:
//  the selection/favorite/delete helpers for the questions list moved here.
//

import SwiftUI

extension QuestionsView {
    /// The question to select after the question with `id` is deleted: the next
    /// visible row, then the previous, mirroring `PadsView.neighborSelection`, so
    /// deleting the open question keeps the detail pane populated instead of
    /// snapping to the empty placeholder. Resolved against `sorted` — the list the
    /// user actually sees.
    func neighborSelection(forDeletedQuestion id: Int) -> Question? {
        let visible = sorted
        guard let index = visible.firstIndex(where: { $0.id == id }) else { return visible.first }

        if visible.indices.contains(index + 1) { return visible[index + 1] }
        if visible.indices.contains(index - 1) { return visible[index - 1] }
        return nil
    }

    /// The account this list belongs to, resolved from its own client rather than
    /// the globally current account (which a race or another window can move),
    /// mirroring `PadsView.owningAccountID`. Falls back to the current account for
    /// clients that don't match a stored account (mocks).
    var owningAccountID: UUID? {
        (accounts.account(matching: client) ?? accounts.currentAccount)?.id
    }

    /// Whether a question mutation notification applies to this single-account view.
    /// Per-org ids collide across accounts, so a bare id from another account must
    /// not mutate this list. An accountless (legacy) event is unambiguous only when
    /// a single account is configured; with several it is dropped rather than
    /// applied to every mounted list (#1211).
    func scopedToThisAccount(_ account: UUID?) -> Bool {
        guard let account else { return accounts.accounts.count <= 1 }

        return account == owningAccountID
    }

    /// How many questions the current filters resolve to, shown as the window's
    /// toolbar subtitle beneath the "Questions" title. Empty when the org has no
    /// questions at all, where a "0 questions" line would just restate the empty list.
    var countSubtitle: String {
        guard !questions.isEmpty else { return "" }

        let count = sorted.count
        return count == 1 ? String(localized: "\(count) question") : String(localized: "\(count) questions")
    }

    /// The iPad drag payload for a question row: the internal `FavoriteDrop` (so it can
    /// be dropped on the sidebar Favorites to pin it, #297) plus the web URL (so external
    /// drops still receive a link). `nil` — non-draggable — when there's no current
    /// account, mirroring `questionPasteboardItem` on macOS.
    func questionFavoritePayload(_ question: Question) -> FavoriteDragPayload? {
        guard let account = accounts.currentAccountID else { return nil }

        return FavoriteDragPayload(
            drop: .question(account: account, id: question.id, title: question.displayTitle),
            url: question.webURL(baseURL: client.baseURL)
        )
    }

    /// Delete several selected questions at once, looping the same per-question API
    /// path the detail view uses (delete, then broadcast so every list drops the row
    /// and the selection follows). `account` is a snapshot of the account that owned
    /// the questions when the delete was scheduled — the undo grace period can
    /// outlive an account switch, and both the requests and the broadcast must stay
    /// bound to the account actually deleted from, not whatever is current at fire
    /// time (#1013, #1209). Failures are aggregated into one report naming the
    /// questions that remain, rather than each failure overwriting the previous
    /// one (#1208).
    func bulkDelete(_ questions: [Question], account: Account?) async {
        // Stop before issuing anything if the owning account was removed or re-keyed
        // during the undo window: its captured client would fire destructive deletes
        // through credentials the user just revoked or replaced (#1209, #2344).
        guard BulkDeleteUndo.accountStillUsable(account, in: accounts) else {
            bulkDeleteError = BulkDeleteUndo.credentialsChangedReport
            return
        }

        let outcome = await BulkDeleteRunner.run(
            questions,
            title: \.displayTitle,
            onProgress: { bulkDeleteProgress = $0 },
            delete: { question in
                do {
                    try await client.deleteQuestion(id: question.id)
                    AppRouter.questionDeleted(id: question.id, account: account?.id, via: client)
                    return nil
                } catch {
                    return error
                }
            }
        )
        bulkDeleteProgress = nil
        bulkDeleteError = BulkDeleteUndo.report(outcome, total: questions.count, kind: .questions)
    }

    func toggleFavorite(_ question: Question) {
        // The view's own account, not the globally current one: a multiwindow or
        // account-switch race must not star a visible question from account A
        // under account B's colliding numeric id (#1210).
        guard let account = owningAccountID else { return }

        favorites.toggle(question.id, title: question.displayTitle, account: account, undoManager: undoManager)
        // Unstarring the last favorite hides the Favorites chip, so drop the
        // filter too — otherwise it would strand the list on an empty result with
        // no visible control to turn it back off. Read the store live: the
        // memoized `favoriteIDSet` is only rebuilt at the top of `body`, so it
        // still contains the id the toggle above just removed (#1008).
        if favoritesOnly, !hasAnyFavorites {
            favoritesOnly = false
        }
    }
}
