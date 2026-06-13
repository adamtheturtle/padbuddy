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
    /// question id -> owning account id. Question ids are global database ids, so a
    /// collision across orgs is not expected; if one ever occurred, the
    /// last-published account wins.
    private(set) var questionAccountID: [Int: UUID] = [:]

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
