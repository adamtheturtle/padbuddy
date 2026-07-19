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

/// Endpoint stamping for persisted merged row ids (#1236): a saved value is an
/// account-namespaced row id, but an account re-pointed at a different server
/// keeps its UUID, so the id alone could reopen an unrelated same-slug resource
/// on the new server. Each persisted row id is stamped with its account's
/// endpoint; a restore drops the value when the endpoint no longer matches.
@MainActor
enum MergedRowPersistence {
    /// The endpoint stamp to store alongside `rowID`, or `""` when there is
    /// nothing to stamp (no row, or an account that no longer resolves).
    ///
    /// Callers hold this in scene storage next to the row id itself rather than
    /// in a sibling `UserDefaults` key, so the pair is restored to the window it
    /// belongs to (#2560-#2563).
    static func endpoint(forRowID rowID: String?) -> String {
        guard let rowID, let uuid = accountUUID(fromRowID: rowID),
              let account = AccountsStore.shared.accounts.first(where: { $0.id == uuid })
        else { return "" }

        return account.resolvedBaseURL.absoluteString
    }

    /// `saved` unless its account now points at a different endpoint than when it
    /// was stamped. A value with no stamp (legacy, or a bare pre-#758 slug) passes
    /// through untouched.
    static func validatedRowID(_ saved: String, endpoint stamped: String) -> String? {
        guard !saved.isEmpty else { return nil }
        guard let uuid = accountUUID(fromRowID: saved), !stamped.isEmpty else { return saved }
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == uuid }),
              account.resolvedBaseURL.absoluteString == stamped else { return nil }

        return saved
    }

    private static func accountUUID(fromRowID id: String) -> UUID? {
        guard let separator = id.firstIndex(of: ":") else { return nil }

        return UUID(uuidString: String(id[..<separator]))
    }
}

@MainActor
final class TopRowPersistenceDebouncer {
    private var task: Task<Void, Never>?
    private var pendingAction: (@MainActor () -> Void)?
    private var generation = 0

    deinit {
        task?.cancel()
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        pendingAction = action
        generation += 1
        guard task == nil else { return }

        task = Task { @MainActor in
            var observedGeneration = generation
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }

                if observedGeneration != generation {
                    observedGeneration = generation
                    continue
                }

                let action = pendingAction
                pendingAction = nil
                task = nil
                action?()
                return
            }
        }
    }
}

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
    func apply(_ saved: NamedSearch) {
        search = saved.search
        stateFilter = saved.stateFilter
        languageFilter = saved.languageFilter
        ownerFilter = saved.ownerFilter
        // Restored validated, matching `PadsView.apply` (#1652).
        typeFilter = FilterValueValidation.interviewType(saved.typeFilter)
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

        let snapshot = MergedFilterSnapshot(search: captureCurrentSearch(),
                                            accountFilter: accountFilter,
                                            mineOnly: mineOnly)
        do {
            let data = try JSONEncoder().encode(snapshot)
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

        if let snapshot = try? JSONDecoder().decode(MergedFilterSnapshot.self, from: data) {
            apply(snapshot.search)
            // Reset before conditionally re-applying: a saved filter whose account
            // was removed must restore as unfiltered rather than leaving any prior
            // in-memory value applied (#1656). Only an account that still resolves
            // to a mergeable one re-applies; a removed account's filter would show
            // an empty list.
            accountFilter = nil
            if let id = snapshot.accountFilter,
               accounts.mergeableAccounts.contains(where: { $0.id == id }) {
                accountFilter = id
            }
            mineOnly = snapshot.mineOnly
        } else if let legacy = try? JSONDecoder().decode(NamedSearch.self, from: data) {
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
    func restoreSelectedPadIfNeeded() {
        var availableRowIDs: Set<String> = []
        // The row id per slug for normalizing a value saved by a build before
        // #758 (a bare slug, no account prefix) — kept only for slugs owned by
        // exactly one account. Account ordering can change across launches, so
        // first-match normalization could reopen a colliding slug from a
        // different server; ambiguous legacy slugs are dropped instead (#1231).
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
        guard !didRestoreSelection, !availableRowIDs.isEmpty else { return }

        didRestoreSelection = true
        let hasPendingOpen = nav.pendingMergedFavoritePad != nil || pendingSelectPadSlug != nil
        if let id = PadsView.padToRestore(
            savedID: Self.normalizedSavedRowID(
                MergedRowPersistence.validatedRowID(persistedSelectedPad,
                                                    endpoint: persistedSelectedPadEndpoint),
                rowIDBySlug: rowIDBySlug
            ),
            hasSelection: selection != nil,
            hasPendingOpen: hasPendingOpen,
            availableIDs: availableRowIDs
        ) {
            // Not a fresh open: marking it would clear the pad's "new activity"
            // dot before the user ever saw it (#1043), mirroring `PadsView`.
            isRestoringSelection = true
            selectedIDs = [id]
            // Bring the restored row into view; the List won't scroll to it on its own.
            pendingScrollToID = id
        } else if selection == nil, !hasPendingOpen,
                  let topID = Self.normalizedSavedRowID(
                      MergedRowPersistence.validatedRowID(persistedTopRow,
                                                          endpoint: persistedTopRowEndpoint),
                      rowIDBySlug: rowIDBySlug
                  ),
                  availableRowIDs.contains(topID) {
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
    func resolvePendingSlugSelection() {
        guard let slug = pendingSelectPadSlug else { return }

        let owners = accounts.mergeableAccounts.filter {
            padsByAccount[$0.id]?.contains(where: { $0.id == slug }) == true
        }
        guard !owners.isEmpty else { return }

        pendingSelectPadSlug = nil
        guard owners.count == 1, let owner = owners.first else { return }

        let rowID = Self.rowID(account: owner.id, pad: slug)
        selectedIDs = [rowID]
        pendingScrollToID = rowID
    }
}
