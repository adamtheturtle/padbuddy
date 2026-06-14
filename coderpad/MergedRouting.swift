//
//  MergedRouting.swift
//  coderpad
//
//  Per-item account routing for the combined "All Accounts" view. The merged pad
//  and question lists fan out across every real account, so a selected pad — or a
//  per-row action like delete — must talk to the API of the account that pad came
//  from, not a single global client. The merged lists publish a pad/question id ->
//  account map here as they load; the detail pane and row actions resolve the right
//  account (and client) through it.
//

import Foundation

@Observable
final class MergedRouting {
    static let shared = MergedRouting()
    private init() {}

    /// pad id -> owning account id. Pad ids are CoderPad slugs (globally unique), so
    /// this is unambiguous across accounts.
    private(set) var padAccountID: [String: UUID] = [:]
    /// question id -> owning account id. Question ids are numbered **per org**, so
    /// two accounts routinely share the same id; this map collapses on collision
    /// (last-published account wins). Disambiguation for the *selected* question
    /// therefore goes through `selectedQuestionAccountID`, set by the combined list.
    private(set) var questionAccountID: [Int: UUID] = [:]

    /// The account of the currently-selected merged question. Set by the combined
    /// questions list as its selection changes (it knows each row's source
    /// account), so the detail pane routes to the right client even when two
    /// accounts share a per-org question id.
    var selectedQuestionAccountID: UUID?

    /// A favourite question chosen from the sidebar in the merged view, carrying its
    /// account so the combined questions list selects the right row — per-org ids
    /// collide, so the id alone is ambiguous. Set by the sidebar, consumed and cleared
    /// by `MergedQuestionsView`.
    var pendingFavoriteQuestion: PendingFavorite?

    /// Switch-to-merged-questions request for a sidebar favourite: the question id and
    /// the account it belongs to.
    struct PendingFavorite: Equatable {
        let account: UUID
        let id: Int
    }

    func selectFavoriteQuestion(account: UUID, id: Int) {
        pendingFavoriteQuestion = PendingFavorite(account: account, id: id)
    }

    /// Replace the pad routing map with the accounts that own the currently merged
    /// pads. Replacing (rather than merging) keeps the map from growing without
    /// bound as lists refresh, and drops entries for pads that no longer appear.
    func setPadRoutes(_ routes: [String: UUID]) {
        padAccountID = routes
    }

    func setQuestionRoutes(_ routes: [Int: UUID]) {
        questionAccountID = routes
    }

    /// The account that owns the pad with `id`, resolved against the live account
    /// list so a removed account never routes anywhere.
    func account(forPadID id: String) -> Account? {
        guard let accountID = padAccountID[id] else { return nil }
        return AccountsStore.shared.accounts.first { $0.id == accountID }
    }

    func account(forQuestionID id: Int) -> Account? {
        guard let accountID = questionAccountID[id] else { return nil }
        return AccountsStore.shared.accounts.first { $0.id == accountID }
    }
}

/// A pad or question paired with the account it belongs to, used as the row model
/// in the merged lists. `id` namespaces the item id by account so the SwiftUI
/// `ForEach`/selection identity stays unique even if two orgs ever shared an item
/// id.
struct AccountScoped<Item>: Identifiable {
    let account: Account
    let item: Item
    let id: String
}
