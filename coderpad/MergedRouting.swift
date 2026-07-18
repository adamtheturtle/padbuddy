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
//  One instance per scene, owned by `ContentView` and injected into its window's
//  environment: routing state used to be a process-wide singleton, so selecting a
//  question or drilling into a Screen campaign in one window retargeted the detail
//  pane (and its account-scoped actions) in every other window (#888, #911).
//

import Foundation

@Observable
final class MergedRouting {

    /// pad id -> owning account id. Pad slugs are only unique per server, so two
    /// custom CoderPad servers can issue the same slug and this map collapses on
    /// collision (last-published account wins). Disambiguation for the *selected*
    /// pad therefore goes through `selectedPadAccountID`, set by the combined
    /// list (#758).
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

    /// The account of the currently-selected merged pad. Set by the combined pads
    /// list as its selection changes (it knows each row's source account), so the
    /// detail pane routes to the right client even when two custom servers share
    /// a pad slug (#758).
    var selectedPadAccountID: UUID?

    /// The account of the campaign drilled into in the combined Screen view (#442).
    /// Set by `MergedScreenView` as the drill-down changes, so the detail column
    /// routes a selected test session's report to that account's `ScreenClient` —
    /// campaign and test ids are numbered per org, so the account must travel with
    /// the selection. `nil` at the campaigns list (no campaign open).
    var selectedScreenAccountID: UUID?

    // The pending sidebar-favourite selections (`pendingMergedFavoriteQuestion`,
    // `pendingMergedFavoritePad`) live on `AppNavigation`: they are durable
    // navigation *requests* also queued by global entry points (Spotlight, the
    // command palette), while this type holds only this window's routing state.

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

// `AccountScoped<Account, Item>` — the account-tagged row model for the merged lists —
// now lives in buddy-kit's BuddyAppKit (shared with RankBuddy, #566) and is available
// here via the `@_exported import BuddyAppKit` umbrella in BuddyAppKit.swift. The pad/
// question rows pass an explicit `id` (the pad slug / namespaced question id) so the
// SwiftUI `ForEach`/selection identity is unchanged.
