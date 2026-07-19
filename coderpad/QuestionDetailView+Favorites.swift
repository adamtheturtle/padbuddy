//
//  QuestionDetailView+Favorites.swift
//  coderpad
//
//  The detail view's favorite star, split from QuestionDetailView.swift to keep
//  that file under the type-body and file-length limits.
//

import SwiftUI

extension QuestionDetailView {
    /// The account whose favorites the star reads and writes. `accountID` is the
    /// question's owning account (question ids are only unique per organization);
    /// in All Accounts the *current* account is merely the last single-account
    /// selection, so keying favorites by it starred the same numeric id under the
    /// wrong account and the detail star disagreed with the merged list's
    /// (#696, #868). Falls back to the current account only when the owner is
    /// genuinely unknown.
    var owningAccountID: UUID? {
        accountID ?? accounts.currentAccountID
    }

    /// Whether the displayed question is a favorite of its owning account, so the
    /// toolbar star can reflect and toggle its state.
    var isFavorite: Bool {
        favorites.isFavorite(question.id, account: owningAccountID)
    }

    func toggleFavorite() {
        guard let account = owningAccountID else { return }

        favorites.toggle(question.id, title: question.displayTitle, account: account, undoManager: undoManager)
    }

    // Honors a "New Pad from Question" request routed via `AppNavigation` (e.g.
    // from the Questions list's context menu): create the pad and open it in the
    // user's browser.
}
