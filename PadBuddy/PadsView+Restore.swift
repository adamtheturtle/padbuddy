//
//  PadsView+Restore.swift
//  coderpad
//
//  Per-account persistence and restore of the Pads list's "place": the open pad and
//  the free-scroll position (#273). Mirrors QuestionsView+Restore.swift.
//

import SwiftUI

extension PadsView {
    // MARK: - Selection persistence

    static func selectedPadKey(_ account: UUID) -> String {
        "pads.selectedPad.\(account.uuidString)"
    }

    /// Persist the id of the pad currently shown in the detail pane, per account, so
    /// the list reopens to it next launch. Skipped until the restore has run so the
    /// empty startup state can't clobber the saved id; clearing the selection removes
    /// the stored id so a blank detail pane is also restored faithfully. Takes the id
    /// and owning account captured when the change happened: the write is deferred,
    /// and reading them at run time let a fast account switch save one account's row
    /// id under another account's key (#757).
    func persistSelectedPad(_ selectedID: String?, account: UUID?) {
        guard didRestoreSelection, let account else { return }

        let key = Self.selectedPadKey(account)
        if let selectedID {
            UserDefaults.standard.set(selectedID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func topRowKey(_ account: UUID) -> String {
        "pads.topRow.\(account.uuidString)"
    }

    /// Persist the id of the row at the top of the list viewport, per account, so an
    /// *unselected* list reopens scrolled to roughly where it was left (#273) — the
    /// selection restore already covers the selected case. Guarded by the selection
    /// restore so the empty startup state can't clobber the saved id.
    func persistTopRow(_ id: String?, account: UUID?) {
        guard didRestoreSelection, let account else { return }

        let key = Self.topRowKey(account)
        if let id {
            UserDefaults.standard.set(id, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func scheduleTopRowPersistence(_ id: String?) {
        // Capture the owning account now: the write is deferred, and a fast account
        // switch would otherwise save this account's top row under the next
        // account's key (#757).
        // The list epoch is captured for the same reason within one account: a reload
        // replaces the rows, and a callback queued against the old ones must not
        // overwrite a scroll position taken since (#2492).
        let account = accounts.currentAccountID
        let epoch = padsRevision
        let restorationGeneration = AppStateRestorationReset.generation
        topRowPersistTask?.cancel()
        topRowPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, epoch == padsRevision,
                  restorationGeneration == AppStateRestorationReset.generation else { return }

            persistTopRow(id, account: account)
        }
    }

    /// The saved pad to reselect on launch: the stored id, but only when nothing is
    /// already selected, no deep link is pending, and the id is still in the loaded
    /// list. Pure so the restore decision is unit-testable in isolation.
    static func padToRestore(
        savedID: String?,
        hasSelection: Bool,
        hasPendingOpen: Bool,
        availableIDs: Set<String>
    ) -> String? {
        guard !hasSelection, !hasPendingOpen,
              let savedID, availableIDs.contains(savedID) else { return nil }

        return savedID
    }

    /// Restore the previously-open pad once its list is loaded. Marks the restore
    /// complete as soon as pads exist (so later selection changes persist), then
    /// reselects via `padToRestore`.
    /// Whether a queued open-pad request is going to claim this list's selection.
    ///
    /// The request carries the account it was raised for, so one aimed at a different
    /// account has no bearing here — blocking on any queued request at all threw away
    /// this account's saved selection for navigation that was never going to land in
    /// it (#2489). A request with no account is unscoped and still wins.
    private var hasPendingOpenForThisAccount: Bool {
        guard let request = nav.openPadRequest else { return false }
        guard let requested = request.accountID else { return true }

        return requested == accounts.currentAccountID
    }

    /// `loadComplete` is true only once the incremental load has finished. Until then a
    /// saved id that isn't in the list yet may simply be on a page still arriving, so
    /// the one-shot restore waits rather than being spent on a partial list (#2490).
    func restoreSelectedPadIfNeeded(loadComplete: Bool = false) {
        guard !didRestoreSelection, !pads.isEmpty else { return }
        guard let account = accounts.currentAccountID else { return }

        let availableIDs = Set(pads.map(\.id))
        let saved = UserDefaults.standard.string(forKey: Self.selectedPadKey(account))
        let savedTop = UserDefaults.standard.string(forKey: Self.topRowKey(account))
        if !loadComplete,
           [saved, savedTop].contains(where: { $0.map { !availableIDs.contains($0) } ?? false }) {
            return
        }

        didRestoreSelection = true
        // The load has finished and these ids aren't in it, so the pads are gone. Clear
        // them rather than rechecking the same dead ids on every launch (#2491).
        if let saved, !availableIDs.contains(saved) {
            UserDefaults.standard.removeObject(forKey: Self.selectedPadKey(account))
        }
        if let savedTop, !availableIDs.contains(savedTop) {
            UserDefaults.standard.removeObject(forKey: Self.topRowKey(account))
        }
        if let id = Self.padToRestore(
            savedID: saved,
            hasSelection: selection != nil,
            hasPendingOpen: hasPendingOpenForThisAccount,
            availableIDs: availableIDs
        ) {
            isRestoringSelection = true
            selectedIDs = [id]
            // Bring the restored row into view; the List won't scroll to it on its own.
            pendingScrollToID = id
        } else if selection == nil, !hasPendingOpenForThisAccount,
                  let topID = savedTop, availableIDs.contains(topID) {
            // Nothing to reselect — return the unselected list to where it was scrolled
            // last session (#273), without selecting anything.
            pendingScrollToID = topID
        }
    }
}
