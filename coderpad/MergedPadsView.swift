//
//  MergedPadsView.swift
//  coderpad
//
//  The combined "All Accounts" pads list. Fans out across every real account,
//  tags each pad with its source account, and presents one merged, sorted list.
//  Per-row actions and the detail pane route back to the originating account's
//  client via `MergedRouting`. The heavily-engineered single-account `PadsView` is
//  left untouched; this is a parallel, merge-aware list that reuses the same filter
//  predicate (`PadListLogic.matches`), row (`PadRow`), and chip components.
//
//  The view-building members live in `MergedPadsView+List`/`+Bars`/`+Logic`
//  extensions so this primary declaration stays small (the project lints
//  `type_body_length` under `--strict`).
//

import AppKit
import SwiftUI

struct MergedPadsView: View {
    @Environment(\.orgDirectory) var directory
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.openWindow) var openWindow
    @State var accounts = AccountsStore.shared
    @State var router = MergedRouting.shared
    @State var nav = AppNavigation.shared
    @State var cache = PadsCacheStore.shared
    @State var openedStore = PadOpenedStore.shared
    /// The latest pads per account. Seeded from each account's disk cache on appear
    /// for an instant list, then replaced as the live fan-out fetch lands.
    @State var padsByAccount: [UUID: [Pad]] = [:]
    /// The most recent fetch error per account, so one account failing surfaces a
    /// quiet note without blanking the pads the other accounts returned.
    @State var accountErrors: [UUID: String] = [:]
    @State var isLoading = false

    @Binding var selection: Pad?
    @State var selectedID: String?
    @Binding var search: String

    @State var stateFilter: PadState?
    @State var languageFilter: String?
    @State var ownerFilter: String?
    @State var typeFilter: String?
    /// Restrict to a single source account. `nil` shows every account.
    @State var accountFilter: UUID?
    /// Restrict to pads owned by each account's own user. Cross-account "mine",
    /// resolved per source account (ownership is account scoped).
    @State var mineOnly = false
    @State var updatedWindow = PadDateWindow()
    @State var createdWindow = PadDateWindow()

    @State var padPendingDelete: Pad?
    @State var deleteError: String?
    /// The account a New Pad is being created for, chosen from the toolbar menu
    /// since creation is inherently single-account.
    @State var creatingForAccount: Account?

    /// Per-render memo so the several reads of `filtered` in one `body` share a
    /// single filter pass, matching `PadsView`'s approach for large lists.
    @State var filteredCache = FilteredScopedPadsCache()
    /// Per-render memo for the sorted cross-account rows (`scoped`), refreshed
    /// once at the top of `body` so its many readers share a single sort.
    @State var scopedCache = ScopedPadsCache()

    var body: some View {
        // Recompute the sorted rows and the filtered rows once per render; every
        // read below (filter pass, chip options, counts) hits the memos.
        refreshScoped()
        refreshFiltered()
        return decorated
    }
}

/// Memo holding the merged list's filtered rows for one render, mirroring
/// `FilteredPadsCache` in `PadsView`.
final class FilteredScopedPadsCache {
    var rows: [AccountScoped<Pad>] = []
}

/// Memo holding the merged list's sorted cross-account rows for one render, so
/// the many reads of `scoped` in one `body` share a single sort.
final class ScopedPadsCache {
    var rows: [AccountScoped<Pad>] = []
}

struct MergedPadsTaskKey: Hashable {
    let accountKey: String
    let phase: ScenePhase
}
