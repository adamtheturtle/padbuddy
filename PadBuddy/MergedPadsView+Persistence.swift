//
//  MergedPadsView+Persistence.swift
//  coderpad
//
//  Filter and selection persistence for the combined "All Accounts" pads list:
//  saving and restoring the live filters and the open pad across launches. Split
//  out of MergedPadsView+Logic so that file stays under the project's file-length
//  lint, mirroring MergedQuestionsView+Persistence.
//

import os
import SwiftUI

extension MergedPadsView {
    // MARK: - Filter persistence

    /// The shared, cloud-synced last-used filter. Not per-account — the merged
    /// list spans every account — unlike `PadsView`'s per-account key. Each window
    /// keeps its own live filter in scene storage (`persistedLiveFilter`); this is
    /// what a window with none yet is seeded from, and what syncs across devices.
    static var liveFilterKey: String {
        "pads.merged.liveFilter"
    }

    /// Snapshot the structured filters into a `NamedSearch`, reusing the same model
    /// `PadsView` persists. The cross-account `accountFilter` and the `mineOnly`
    /// preset travel in the `MergedFilterSnapshot` envelope around this (#913);
    /// `teamFilter` has no merged equivalent, so it stays nil.
    func captureCurrentSearch() -> NamedSearch {
        NamedSearch(
            name: "", search: search,
            stateFilter: stateFilter, languageFilter: languageFilter,
            ownerFilter: ownerFilter, teamFilter: nil,
            typeFilter: typeFilter,
            updatedWindow: updatedWindow.isActive ? updatedWindow : nil,
            createdWindow: createdWindow.isActive ? createdWindow : nil
        )
    }

    /// Apply a saved snapshot to the live filters. Mirrors `PadsView.apply`, minus
    /// the team filter the merged list doesn't expose.
    ///
    /// The merged-only controls reset first. A `NamedSearch` carries neither the
    /// Mine preset nor the account filter, so leaving them set left a recalled
    /// search silently narrowed by constraints it does not represent — and a
    /// filter to an account that may no longer be mergeable (#2570, #2572). The
    /// restore path re-applies both from its snapshot envelope afterwards.
    func apply(_ saved: NamedSearch) {
        mineOnly = false
        accountFilter = nil
        search = saved.search
        stateFilter = saved.stateFilter
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        // Restored validated, matching `PadsView.apply` (#1652).
        let restoredType = FilterValueValidation.interviewType(saved.typeFilter)
        if saved.typeFilter != nil, restoredType == nil {
            discardedFilterNotice = String(localized: "An invalid saved pad type filter was discarded.")
        }
        typeFilter = restoredType
        updatedWindow = saved.updatedWindow ?? DateWindow()
        createdWindow = saved.createdWindow ?? DateWindow()
    }

    func clearAllFilters() {
        search = ""
        stateFilter = nil
        languageFilter = nil
        ownerFilter = nil
        typeFilter = nil
        accountFilter = nil
        mineOnly = false
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

        // Debounced: this fires on every filter change, including each keystroke in
        // the search field, and the snapshot is only read on the restore-on-appear
        // (#4783).
        LiveFilterPersistence.shared.schedule(key: LiveFilterPersistence.debounceKey(
            storageKey: Self.liveFilterKey,
            scope: liveFilterPersistenceScope
        )) {
            let snapshot = MergedFilterSnapshot(search: captureCurrentSearch(),
                                                accountFilter: accountFilter,
                                                accountFilterSyncID: MergedAccountFilter.syncID(for: accountFilter),
                                                mineOnly: mineOnly)
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
                    "Merged pad filter snapshot failed to encode: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Writes any debounced snapshot immediately, so leaving the pane does not lose
    /// the filters it was showing.
    func flushPersistedFilters() {
        LiveFilterPersistence.shared.flush(key: LiveFilterPersistence.debounceKey(
            storageKey: Self.liveFilterKey,
            scope: liveFilterPersistenceScope
        ))
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
        } else if let legacy = try? SharedCoders.decoder.decode(NamedSearch.self, from: data) {
            apply(legacy)
        } else {
            // A corrupted or schema-incompatible payload would fail again on every
            // launch while leaving stale defaults in place; remove it so the next
            // filter change persists a fresh, decodable snapshot (#1237).
            persistedLiveFilter = ""
            UserDefaults.standard.removeObject(forKey: Self.liveFilterKey)
            persistenceLogger.error("Discarded an undecodable merged pad filter snapshot")
        }
    }

    // MARK: - Selection persistence

    /// Persist the namespaced row id of the pad shown in the detail pane so the
    /// merged list reopens to it next launch. Skipped until the restore has run so
    /// the empty startup state can't clobber the saved id; clearing the selection
    /// removes the stored id so a blank detail pane is restored faithfully too.
    func persistSelectedPad() {
        guard didRestoreSelection else { return }

        // The row id carries its account (#758): pad slugs are only unique per
        // server, so two custom CoderPad servers can issue the same slug and the
        // bare slug couldn't say which account's pad to reopen. The endpoint stamp
        // lets a restore reject the row when the account was re-pointed (#1236).
        persistedSelectedPad = selectedID ?? ""
        persistedSelectedPadEndpoint = MergedRowPersistence.endpoint(forRowID: selectedID)
    }

    /// Persist the namespaced id of the row at the top of the viewport so an
    /// *unselected* merged list reopens scrolled to roughly where it was left (#273).
    /// Guarded by the selection restore so the empty startup state can't clobber it.
    func persistTopRow(_ id: String?) {
        guard didRestoreSelection else { return }

        // Namespaced and stamped for the same reasons as the selection above.
        persistedTopRow = id ?? ""
        persistedTopRowEndpoint = MergedRowPersistence.endpoint(forRowID: id)
    }

    func scheduleTopRowPersistence(_ id: String?) {
        topRowPersistence.schedule {
            persistTopRow(id)
        }
    }

    /// Restore the previously-open pad once a list exists to resolve it against.
    /// Marks the restore complete as soon as pads load (so later changes persist),
    /// then reselects via `PadsView.padToRestore` — the same pure, unit-tested
    /// decision the single-account list uses, over namespaced row ids (#758). Reads
    /// the source dictionary rather than the per-render `scoped` memo, which can
    /// still be empty right after a cache seed.
    /// Every loaded row id, plus the row id per slug used to normalize a value
    /// saved by a build before #758 (a bare slug, no account prefix).
    ///
    /// The slug map keeps only slugs owned by exactly one account. Account ordering
    /// can change across launches, so first-match normalization could reopen a
    /// colliding slug from a different server; ambiguous legacy slugs are dropped
    /// instead (#1231).
    private func loadedRowIndex() -> (rowIDs: Set<String>, rowIDBySlug: [String: String]) {
        var availableRowIDs: Set<String> = []
        var rowIDBySlug: [String: String] = [:]
        var collidingSlugs: Set<String> = []
        for account in accounts.mergeableAccounts {
            for pad in padsByAccount[account.id] ?? [] {
                let rowID = Self.rowID(account: account.id, pad: pad.id)
                availableRowIDs.insert(rowID)
                if rowIDBySlug[pad.id] == nil {
                    rowIDBySlug[pad.id] = rowID
                } else {
                    collidingSlugs.insert(pad.id)
                }
            }
        }
        for slug in collidingSlugs {
            rowIDBySlug[slug] = nil
        }
        return (availableRowIDs, rowIDBySlug)
    }

    /// `loadComplete` is true only at the end of the cross-account fan-out. Until
    /// then a saved row that isn't in the list yet may simply belong to an account
    /// or page still loading, so the one-shot restore waits rather than being spent
    /// on an incomplete list (#2564).
    func restoreSelectedPadIfNeeded(loadComplete: Bool = false) {
        let (availableRowIDs, rowIDBySlug) = loadedRowIndex()
        guard !didRestoreSelection, !availableRowIDs.isEmpty else { return }

        let savedSelection = Self.normalizedSavedRowID(
            MergedRowPersistence.validatedRowID(persistedSelectedPad,
                                                endpoint: persistedSelectedPadEndpoint),
            rowIDBySlug: rowIDBySlug
        )
        let savedTop = Self.normalizedSavedRowID(
            MergedRowPersistence.validatedRowID(persistedTopRow, endpoint: persistedTopRowEndpoint),
            rowIDBySlug: rowIDBySlug
        )
        // A saved row missing from a partial list may still be coming. Spending the
        // restore now would lose it for good, so hold until the fan-out reports in.
        if !loadComplete,
           [savedSelection, savedTop].contains(where: { $0.map { !availableRowIDs.contains($0) } ?? false }) {
            return
        }
        // A legacy bare slug is resolved by looking for the single account that
        // holds it. On a partial list a slug two servers both issue looks unique,
        // so it would resolve to whichever account loaded first and reopen the
        // wrong server's pad. Only decide once every account has reported (#2568).
        if !loadComplete, Self.isLegacyBareSlug(persistedSelectedPad) || Self.isLegacyBareSlug(persistedTopRow) {
            return
        }

        didRestoreSelection = true
        // The load has finished and these rows aren't in it, so they're gone. Drop
        // them rather than rechecking the same dead ids every launch and risking a
        // future row that reuses one being selected without the user asking (#2566).
        if let savedSelection, !availableRowIDs.contains(savedSelection) {
            persistedSelectedPad = ""
            persistedSelectedPadEndpoint = ""
        }
        if let savedTop, !availableRowIDs.contains(savedTop) {
            persistedTopRow = ""
            persistedTopRowEndpoint = ""
        }
        let hasPendingOpen = nav.pendingMergedFavoritePad != nil || pendingSelectPadSlug != nil
        if let id = PadsView.padToRestore(
            savedID: savedSelection,
            hasSelection: selection != nil,
            hasPendingOpen: hasPendingOpen,
            availableIDs: availableRowIDs
        ) {
            // This is a restored selection, not a user-driven selection.
            isRestoringSelection = true
            selectedIDs = [id]
            // Bring the restored row into view; the List won't scroll to it on its own.
            pendingScrollToID = id
        } else if selection == nil, !hasPendingOpen,
                  let topID = savedTop, availableRowIDs.contains(topID) {
            // Nothing to reselect — return the unselected list to where it was scrolled
            // last session (#273), without selecting anything.
            pendingScrollToID = topID
        }
    }

    /// Normalizes a persisted selection/top-row value onto today's account-
    /// namespaced row ids (#758). A current value ("<account uuid>:<slug>") passes
    /// through untouched; a legacy value from a build before #758 - a bare slug -
    /// maps to the loaded row holding that slug when exactly one account does, so
    /// the saved place survives the format change without ever reopening a
    /// colliding slug from a different server (#1231).
    /// Whether a persisted value is in the pre-#758 format: a bare pad slug with
    /// no account prefix, which can only be resolved by searching the loaded rows.
    static func isLegacyBareSlug(_ saved: String) -> Bool {
        guard !saved.isEmpty else { return false }
        guard let separator = saved.firstIndex(of: ":") else { return true }

        return UUID(uuidString: String(saved[..<separator])) == nil
    }

    static func normalizedSavedRowID(_ saved: String?, rowIDBySlug: [String: String]) -> String? {
        guard let saved else { return nil }

        if let separator = saved.firstIndex(of: ":"),
           UUID(uuidString: String(saved[..<separator])) != nil {
            return saved
        }
        return rowIDBySlug[saved]
    }

    /// Completes a slug-only selection request once a matching row loads: the
    /// merged list keys selection by account-namespaced row id (#758), so a bare
    /// slug from a process-wide request (`PadsRequest.selectPadID`) can only be
    /// honored after its row exists. Called from the same lifecycle points as
    /// `restoreSelectedPadIfNeeded()`. Honored only when exactly one merged
    /// account holds the slug: opening an arbitrary account's same-slug pad could
    /// silently show the wrong server's pad, so an ambiguous request is dropped
    /// instead (#1232) — account-carrying requests route via
    /// `pendingMergedFavoritePad` / `PadsRequest.selectPadAccountID`.
    func resolvePendingSlugSelection(loadComplete: Bool = false) {
        guard let slug = pendingSelectPadSlug else { return }

        // Answered from the routing map `publishRoutes()` already maintains, rather
        // than scanning every account's whole pad list on each lifecycle pass — this
        // runs repeatedly while a slug is parked, so it was O(accounts x pads) every
        // time (#2475).
        let ownerCount = router.ownerCount(forPadID: slug)
        guard ownerCount > 0 else {
            if loadComplete {
                pendingSelectPadSlug = nil
                unavailablePadID = slug
            }
            return
        }

        // One owner on a partial list proves nothing: another account that also
        // holds the slug may not have loaded, and acting now would open the first
        // one to arrive rather than refusing the ambiguity (#2569). Wait for the
        // fan-out before deciding — but honour an unambiguous hit right away once
        // it has, so the common single-owner case still resolves promptly.
        guard loadComplete || ownerCount > 1 else { return }

        pendingSelectPadSlug = nil
        guard let owner = router.uniqueAccountID(forPadID: slug) else {
            unavailablePadID = slug
            return
        }

        let rowID = Self.rowID(account: owner, pad: slug)
        selectedIDs = [rowID]
        pendingScrollToID = rowID
    }
}
