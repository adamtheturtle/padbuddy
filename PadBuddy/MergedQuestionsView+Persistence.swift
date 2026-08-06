//
//  MergedQuestionsView+Persistence.swift
//  coderpad
//
//  Filter and selection persistence for the combined "All Accounts" questions
//  list: snapshotting live filters and the open question to UserDefaults, and
//  restoring them on launch.
//

import os
import SwiftUI

extension MergedQuestionsView {
    // MARK: - Filter persistence

    /// The shared, cloud-synced last-used filter. Not per-account — the merged
    /// list spans every account — unlike `QuestionsView`'s per-account key. Each
    /// window keeps its own live filter in scene storage (`persistedLiveFilter`);
    /// this is what a window with none yet is seeded from.
    static var liveFilterKey: String {
        "questions.merged.liveFilter"
    }

    /// Snapshot the structured filters into a `NamedSearch`, reusing the model
    /// `QuestionsView` persists. The cross-account `accountFilter` and the
    /// `mineOnly`/`favoritesOnly` presets travel in the `MergedFilterSnapshot`
    /// envelope around this (#913).
    func captureCurrentSearch() -> NamedSearch {
        NamedSearch(
            name: "", search: search,
            languageFilter: languageFilter, ownerFilter: ownerFilter,
            typeFilter: typeFilter,
            updatedWindow: updatedWindow.isActive ? updatedWindow : nil,
            createdWindow: createdWindow.isActive ? createdWindow : nil,
            draftFilter: draftFilter
        )
    }

    /// Apply a saved snapshot to the live filters. Mirrors `QuestionsView.apply`,
    /// including turning the Favorites preset off (it's mutually exclusive with a
    /// recalled filter set).
    ///
    /// Mine and the account filter reset for the same reason: a `NamedSearch`
    /// represents neither, so leaving them set left a recalled search narrowed by
    /// constraints it does not carry, possibly to an account that is no longer
    /// mergeable (#2571, #2573). The restore path re-applies both from its
    /// snapshot envelope afterwards.
    func apply(_ saved: NamedSearch) {
        favoritesOnly = false
        mineOnly = false
        accountFilter = nil
        search = saved.search
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        // Restored validated, matching `QuestionsView.apply` (#1651, #1653).
        let restoredType = FilterValueValidation.interviewType(saved.typeFilter)
        let restoredDraft = FilterValueValidation.draftState(saved.draftFilter)
        if (saved.typeFilter != nil && restoredType == nil) || (saved.draftFilter != nil && restoredDraft == nil) {
            discardedFilterNotice = String(localized: "Invalid saved question filters were discarded.")
        }
        typeFilter = restoredType
        draftFilter = restoredDraft
        updatedWindow = saved.updatedWindow ?? DateWindow()
        createdWindow = saved.createdWindow ?? DateWindow()
    }

    func clearAllFilters() {
        search = ""
        languageFilter = nil
        ownerFilter = nil
        typeFilter = nil
        draftFilter = nil
        accountFilter = nil
        mineOnly = false
        favoritesOnly = false
        updatedWindow = DateWindow()
        createdWindow = DateWindow()
    }

    var hasActiveFilters: Bool {
        activeFilterCount > 0 || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Persist the current filters so the merged list reopens with the same view.
    /// Skipped until the initial restore has run, so the empty startup state never
    /// clobbers a saved snapshot.
    func persistFilters() {
        guard didRestoreFilters else { return }

        let snapshot = MergedFilterSnapshot(search: captureCurrentSearch(),
                                            accountFilter: accountFilter,
                                            accountFilterSyncID: MergedAccountFilter.syncID(for: accountFilter),
                                            mineOnly: mineOnly,
                                            favoritesOnly: favoritesOnly)
        do {
            let data = try SharedCoders.encoder.encode(snapshot)
            // This window's own copy, and the shared seed for the next new window
            // (which is also what PreferenceCloudSync carries between devices).
            persistedLiveFilter = data.base64EncodedString()
            UserDefaults.standard.set(data, forKey: Self.liveFilterKey)
        } catch {
            // Log rather than silently dropping the write, so a persistent encode
            // failure is diagnosable from Console (#1237).
            persistenceLogger.error(
                "Merged question filter snapshot failed to encode: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Restore the persisted filters once, on appear. Reads the
    /// `MergedFilterSnapshot` envelope, falling back to the bare `NamedSearch`
    /// persisted by earlier builds (#913).
    func restoreFilters() {
        guard !didRestoreFilters else { return }

        didRestoreFilters = true
        // This window's own filter first; a window that has never had one falls
        // back to the shared last-used snapshot so it opens on a familiar view.
        let data = Data(base64Encoded: persistedLiveFilter)
            ?? UserDefaults.standard.data(forKey: Self.liveFilterKey)
        guard let data else { return }

        if let snapshot = try? SharedCoders.decoder.decode(MergedFilterSnapshot.self, from: data) {
            apply(snapshot.search)
            // An unconditional assignment: a saved filter whose account was removed
            // must restore as unfiltered rather than leaving any prior in-memory
            // value applied (#1656). The resolver matches by local id, then by
            // cross-device sync id, and only accepts a still-mergeable account.
            accountFilter = MergedAccountFilter.resolve(snapshot)
            if snapshot.accountFilter != nil, accountFilter == nil {
                discardedFilterNotice = String(
                    localized: "A saved account filter that is no longer available was discarded."
                )
            }
            mineOnly = snapshot.mineOnly
            // After apply(), which turns the preset off for a recalled filter set.
            favoritesOnly = snapshot.favoritesOnly
        } else if let legacy = try? SharedCoders.decoder.decode(NamedSearch.self, from: data) {
            apply(legacy)
        } else {
            // A corrupted or schema-incompatible payload would fail again on every
            // launch while leaving stale defaults in place; remove it so the next
            // filter change persists a fresh, decodable snapshot (#1237).
            persistedLiveFilter = ""
            UserDefaults.standard.removeObject(forKey: Self.liveFilterKey)
            persistenceLogger.error("Discarded an undecodable merged question filter snapshot")
        }
    }

    // MARK: - Selection persistence

    /// Persist the namespaced row id of the question shown in the detail pane so the
    /// merged list reopens to it next launch. Skipped until the restore has run so
    /// the empty startup state can't clobber the saved id; clearing the selection
    /// removes it so a blank detail pane is restored faithfully too.
    func persistSelectedRow() {
        guard didRestoreSelection else { return }

        // The row id carries its account: per-org question ids collide across
        // accounts, so the bare id couldn't say which account's question to reopen.
        // The endpoint stamp lets a restore reject the row when the account was
        // re-pointed at a different server (#1236).
        persistedSelectedRow = selectedRowID ?? ""
        persistedSelectedRowEndpoint = MergedRowPersistence.endpoint(forRowID: selectedRowID)
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

    /// Persist the namespaced id of the row at the top of the viewport so an
    /// *unselected* merged list reopens scrolled to roughly where it was left (#273).
    /// Guarded by the selection restore so the empty startup state can't clobber it.
    func persistTopRow(_ rowID: String?) {
        guard didRestoreSelection else { return }

        // Namespaced and stamped for the same reasons as the selection above.
        persistedTopRow = rowID ?? ""
        persistedTopRowEndpoint = MergedRowPersistence.endpoint(forRowID: rowID)
    }

    func scheduleTopRowPersistence(_ rowID: String?) {
        topRowPersistence.schedule {
            persistTopRow(rowID)
        }
    }

    /// Restore the previously-open question once a list exists to resolve it against.
    /// Marks the restore complete as soon as questions load (so later changes
    /// persist), then reselects via `rowToRestore`. Builds the available row ids from
    /// the source dictionary rather than the per-render `scoped` memo, which can still
    /// be empty right after a cache seed.
    /// `loadComplete` is true only at the end of the cross-account fan-out. Until
    /// then a saved row that isn't in the list yet may simply belong to an account
    /// or page still loading, so the one-shot restore waits rather than being spent
    /// on an incomplete list (#2565).
    func restoreSelectedRowIfNeeded(loadComplete: Bool = false) {
        var availableRowIDs: Set<String> = []
        for account in accounts.mergeableAccounts {
            for question in questionsByAccount[account.id] ?? [] {
                availableRowIDs.insert(Self.rowID(account: account.id, question: question.id))
            }
        }
        guard !didRestoreSelection, !availableRowIDs.isEmpty else { return }

        let savedSelection = MergedRowPersistence.validatedRowID(persistedSelectedRow,
                                                                 endpoint: persistedSelectedRowEndpoint)
        let savedTop = MergedRowPersistence.validatedRowID(persistedTopRow,
                                                           endpoint: persistedTopRowEndpoint)
        // A saved row missing from a partial list may still be coming. Spending the
        // restore now would lose it for good, so hold until the fan-out reports in.
        if !loadComplete,
           [savedSelection, savedTop].contains(where: { $0.map { !availableRowIDs.contains($0) } ?? false }) {
            return
        }

        didRestoreSelection = true
        // The load has finished and these rows aren't in it, so they're gone. Drop
        // them rather than rechecking the same dead ids every launch — and leaving
        // private identifiers persisted indefinitely — and risking a recreated
        // question that reuses one being selected without the user asking (#2567).
        if let savedSelection, !availableRowIDs.contains(savedSelection) {
            persistedSelectedRow = ""
            persistedSelectedRowEndpoint = ""
        }
        if let savedTop, !availableRowIDs.contains(savedTop) {
            persistedTopRow = ""
            persistedTopRowEndpoint = ""
        }
        if let rowID = Self.rowToRestore(
            savedRowID: savedSelection,
            hasSelection: selection != nil,
            hasPendingNavigation: nav.pendingMergedFavoriteQuestion != nil,
            availableRowIDs: availableRowIDs
        ) {
            selectedRowIDs = [rowID]
            // Bring the restored row into view; the List won't scroll to it on its own.
            pendingScrollToRowID = rowID
        } else if selection == nil, nav.pendingMergedFavoriteQuestion == nil,
                  let topID = savedTop, availableRowIDs.contains(topID) {
            // Nothing to reselect — return the unselected list to where it was scrolled
            // last session (#273), without selecting anything.
            pendingScrollToRowID = topID
        }
    }
}
