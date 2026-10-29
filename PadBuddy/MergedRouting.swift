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
    /// pad id -> owning account ids. Pad slugs are only unique per server, so two
    /// custom CoderPad servers can issue the same slug; up to two distinct owners
    /// distinguish "unknown", "unique", and "ambiguous" without retaining every
    /// owner of a colliding slug. Bare-slug lookups refuse collisions (#1215).
    /// Disambiguation for the *selected* pad goes through
    /// `selectedPadAccountID`, set by the combined list (#758).
    private(set) var padOwners: [String: Set<UUID>] = [:]
    /// question id -> owning account ids. Question ids are numbered **per org**,
    /// so two accounts routinely share the same id. Bare-id lookups must refuse
    /// ambiguous ownership (#1219). Disambiguation for the *selected* question goes
    /// through `selectedQuestionAccountID`, set by the combined list.
    private(set) var questionOwners: [Int: Set<UUID>] = [:]

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
    func setPadRoutes(_ routes: [String: Set<UUID>]) {
        padOwners = routes
    }

    func setQuestionRoutes(_ routes: [Int: Set<UUID>]) {
        questionOwners = routes
    }

    /// The single account id owning the pad with `id`, or nil when the slug is
    /// unknown **or shared by several merged accounts** — an ambiguous bare id
    /// must not route to an arbitrary owner (#1215).
    func uniqueAccountID(forPadID id: String) -> UUID? {
        guard let owners = padOwners[id], owners.count == 1 else { return nil }

        return owners.first
    }

    /// Zero for unknown, one for unique ownership, or at least two for ambiguity.
    /// The bounded pad index retains only enough owners to detect ambiguity.
    func ownerCount(forPadID id: String) -> Int {
        padOwners[id]?.count ?? 0
    }

    /// The question counterpart to ``uniqueAccountID(forPadID:)`` (#1219).
    func uniqueAccountID(forQuestionID id: Int) -> UUID? {
        guard let owners = questionOwners[id], owners.count == 1 else { return nil }

        return owners.first
    }

    /// The account that owns the pad with `id`, resolved against the live account
    /// list so a removed account never routes anywhere. Nil when the slug is
    /// shared by several merged accounts (#1215).
    func account(forPadID id: String) -> Account? {
        guard let accountID = uniqueAccountID(forPadID: id) else { return nil }

        return AccountsStore.shared.accounts.first { $0.id == accountID }
    }

    func account(forQuestionID id: Int) -> Account? {
        guard let accountID = uniqueAccountID(forQuestionID: id) else { return nil }

        return AccountsStore.shared.accounts.first { $0.id == accountID }
    }
}

// `AccountScoped<Account, Item>` — the account-tagged row model for the merged lists —
// now lives in buddy-kit's BuddyAppKit (shared with RankBuddy, #566) and is available
// here via the `@_exported import BuddyAppKit` umbrella in BuddyAppKit.swift. The pad/
// question rows pass an explicit `id` (the pad slug / namespaced question id) so the
// SwiftUI `ForEach`/selection identity is unchanged.
