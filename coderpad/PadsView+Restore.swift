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
        let account = accounts.currentAccountID
        topRowPersistTask?.cancel()
        topRowPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }

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
    /// reselects via `padToRestore`. Sets `isRestoringSelection` so the reselection
    /// doesn't count as freshly opening the pad (which would clear its activity dot).
    func restoreSelectedPadIfNeeded() {
        guard !didRestoreSelection, !pads.isEmpty else { return }

        didRestoreSelection = true
        guard let account = accounts.currentAccountID else { return }

        if let id = Self.padToRestore(
            savedID: UserDefaults.standard.string(forKey: Self.selectedPadKey(account)),
            hasSelection: selection != nil,
            hasPendingOpen: nav.openPadID != nil,
            availableIDs: Set(pads.map(\.id))
        ) {
            isRestoringSelection = true
            selectedIDs = [id]
            // Bring the restored row into view; the List won't scroll to it on its own.
            pendingScrollToID = id
        } else if selection == nil, nav.openPadID == nil,
                  let topID = UserDefaults.standard.string(forKey: Self.topRowKey(account)),
                  pads.contains(where: { $0.id == topID }) {
            // Nothing to reselect — return the unselected list to where it was scrolled
            // last session (#273), without selecting anything.
            pendingScrollToID = topID
        }
    }
}
