//
//  MergedQuestionsView+Persistence.swift
//  coderpad
//
//  Filter and selection persistence for the combined "All Accounts" questions
//  list: snapshotting live filters and the open question to UserDefaults, and
//  restoring them on launch.
//

import SwiftUI

extension MergedQuestionsView {
    // MARK: - Filter persistence

    /// The single key for the merged list's live filters. Not per-account — the
    /// merged list spans every account — unlike `QuestionsView`'s per-account key.
    static var liveFilterKey: String {
        "questions.merged.liveFilter"
    }

    /// Snapshot the structured filters into a `NamedSearch`, reusing the model
    /// `QuestionsView` persists. The cross-account `accountFilter`, the `mineOnly`
    /// preset, and the `favoritesOnly` preset are intentionally left out, matching how
    /// the single-account list omits its own presets.
    func captureCurrentSearch() -> NamedSearch {
        NamedSearch(
            name: "", search: search,
            languageFilter: languageFilter, ownerFilter: ownerFilter,
            typeFilter: typeFilter, draftFilter: draftFilter
        )
    }

    /// Apply a saved snapshot to the live filters. Mirrors `QuestionsView.apply`,
    /// including turning the Favorites preset off (it's mutually exclusive with a
    /// recalled filter set).
    func apply(_ saved: NamedSearch) {
        favoritesOnly = false
        search = saved.search
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        typeFilter = saved.typeFilter
        draftFilter = saved.draftFilter
    }

    /// Persist the current filters so the merged list reopens with the same view.
    /// Skipped until the initial restore has run, so the empty startup state never
    /// clobbers a saved snapshot.
    func persistFilters() {
        guard didRestoreFilters else { return }
        if let data = try? JSONEncoder().encode(captureCurrentSearch()) {
            UserDefaults.standard.set(data, forKey: Self.liveFilterKey)
        }
    }

    /// Restore the persisted filters once, on appear.
    func restoreFilters() {
        guard !didRestoreFilters else { return }
        didRestoreFilters = true
        guard let data = UserDefaults.standard.data(forKey: Self.liveFilterKey),
              let snapshot = try? JSONDecoder().decode(NamedSearch.self, from: data) else { return }
        apply(snapshot)
    }

    // MARK: - Selection persistence

    /// The single key for the merged list's open question, stored as the account-
    /// namespaced row id (`rowID(account:question:)`). Per-org question ids collide
    /// across accounts, so the bare id couldn't say which account's question to
    /// reopen — the persisted value must carry its account.
    static var selectedRowKey: String {
        "questions.merged.selectedRow"
    }

    /// Persist the namespaced row id of the question shown in the detail pane so the
    /// merged list reopens to it next launch. Skipped until the restore has run so
    /// the empty startup state can't clobber the saved id; clearing the selection
    /// removes it so a blank detail pane is restored faithfully too.
    func persistSelectedRow() {
        guard didRestoreSelection else { return }
        if let selectedRowID {
            UserDefaults.standard.set(selectedRowID, forKey: Self.selectedRowKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedRowKey)
        }
    }

    /// The saved row to reselect on launch: the stored namespaced row id, but only
    /// when nothing is already selected, no navigation is pending, and the row is
    /// still in the loaded list. Pure so the restore decision is unit-testable in
    /// isolation, mirroring `QuestionsView.questionToRestore`.
    static func rowToRestore(
        savedRowID: String?,
        hasSelection: Bool,
        hasPendingNavigation: Bool,
        availableRowIDs: Set<String>
    ) -> String? {
        guard !hasSelection, !hasPendingNavigation,
              let savedRowID, availableRowIDs.contains(savedRowID) else { return nil }
        return savedRowID
    }

    /// Restore the previously-open question once a list exists to resolve it against.
    /// Marks the restore complete as soon as questions load (so later changes
    /// persist), then reselects via `rowToRestore`. Builds the available row ids from
    /// the source dictionary rather than the per-render `scoped` memo, which can still
    /// be empty right after a cache seed.
    func restoreSelectedRowIfNeeded() {
        var availableRowIDs: Set<String> = []
        for account in accounts.mergeableAccounts {
            for question in questionsByAccount[account.id] ?? [] {
                availableRowIDs.insert(Self.rowID(account: account.id, question: question.id))
            }
        }
        guard !didRestoreSelection, !availableRowIDs.isEmpty else { return }
        didRestoreSelection = true
        guard let rowID = Self.rowToRestore(
            savedRowID: UserDefaults.standard.string(forKey: Self.selectedRowKey),
            hasSelection: selection != nil,
            hasPendingNavigation: router.pendingFavoriteQuestion != nil,
            availableRowIDs: availableRowIDs
        ) else { return }
        selectedRowIDs = [rowID]
        // Bring the restored row into view; the List won't scroll to it on its own.
        pendingScrollToRowID = rowID
    }
}
