//
//  MergedPadsView+Persistence.swift
//  coderpad
//
//  Filter and selection persistence for the combined "All Accounts" pads list:
//  saving and restoring the live filters and the open pad across launches. Split
//  out of MergedPadsView+Logic so that file stays under the project's file-length
//  lint, mirroring MergedQuestionsView+Persistence.
//

import SwiftUI

@MainActor
final class TopRowPersistenceDebouncer {
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

            action()
        }
    }
}

extension MergedPadsView {
    // MARK: - Filter persistence

    /// The single key for the merged list's live filters. Not per-account — the
    /// merged list spans every account — unlike `PadsView`'s per-account key.
    static var liveFilterKey: String {
        "pads.merged.liveFilter"
    }

    /// Snapshot the structured filters into a `NamedSearch`, reusing the same model
    /// `PadsView` persists. The cross-account `accountFilter` and the `mineOnly`
    /// preset are intentionally left out, matching how the single-account list omits
    /// its own presets; `teamFilter` has no merged equivalent, so it stays nil.
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
        typeFilter = saved.typeFilter
        updatedWindow = saved.updatedWindow ?? DateWindow()
        createdWindow = saved.createdWindow ?? DateWindow()
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

    /// The single key for the merged list's open pad. Pad ids are globally unique
    /// across accounts, so the merged selection needs no account namespacing (unlike
    /// merged questions, whose per-org ids collide and must carry their account).
    static var selectedPadKey: String {
        "pads.merged.selectedPad"
    }

    /// Persist the id of the pad shown in the detail pane so the merged list reopens
    /// to it next launch. Skipped until the restore has run so the empty startup
    /// state can't clobber the saved id; clearing the selection removes the stored id
    /// so a blank detail pane is restored faithfully too.
    func persistSelectedPad() {
        guard didRestoreSelection else { return }

        if let selectedID {
            UserDefaults.standard.set(selectedID, forKey: Self.selectedPadKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedPadKey)
        }
    }

    /// The single key for the merged list's free-scroll position (top visible row),
    /// no account namespacing for the same reason as `selectedPadKey`.
    static var topRowKey: String {
        "pads.merged.topRow"
    }

    /// Persist the id of the row at the top of the viewport so an *unselected* merged
    /// list reopens scrolled to roughly where it was left (#273). Guarded by the
    /// selection restore so the empty startup state can't clobber it.
    func persistTopRow(_ id: String?) {
        guard didRestoreSelection else { return }

        if let id {
            UserDefaults.standard.set(id, forKey: Self.topRowKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.topRowKey)
        }
    }

    func scheduleTopRowPersistence(_ id: String?) {
        topRowPersistence.schedule {
            persistTopRow(id)
        }
    }

    /// Restore the previously-open pad once a list exists to resolve it against.
    /// Marks the restore complete as soon as pads load (so later changes persist),
    /// then reselects via `PadsView.padToRestore` — the same pure, unit-tested
    /// decision the single-account list uses. Reads the source dictionary rather than
    /// the per-render `scoped` memo, which can still be empty right after a cache seed.
    func restoreSelectedPadIfNeeded() {
        let availableIDs = Set(padsByAccount.values.flatMap(\.self).map(\.id))
        guard !didRestoreSelection, !availableIDs.isEmpty else { return }

        didRestoreSelection = true
        if let id = PadsView.padToRestore(
            savedID: UserDefaults.standard.string(forKey: Self.selectedPadKey),
            hasSelection: selection != nil,
            hasPendingOpen: router.pendingFavoritePadID != nil,
            availableIDs: availableIDs
        ) {
            selectedIDs = [id]
            // Bring the restored row into view; the List won't scroll to it on its own.
            pendingScrollToID = id
        } else if selection == nil, router.pendingFavoritePadID == nil,
                  let topID = UserDefaults.standard.string(forKey: Self.topRowKey),
                  availableIDs.contains(topID) {
            // Nothing to reselect — return the unselected list to where it was scrolled
            // last session (#273), without selecting anything.
            pendingScrollToID = topID
        }
    }
}
