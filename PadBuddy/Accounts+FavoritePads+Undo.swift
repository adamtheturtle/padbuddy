//
//  Accounts+FavoritePads+Undo.swift
//  coderpad
//
//  Undo registration and restoration for favorite pads, split out of
//  Accounts+FavoritePads.swift for file length. `restore` and `registerUndo` are
//  module-internal rather than private so the two halves can see each other, as
//  .swiftlint.yml documents for these splits.
//

import Foundation
import SwiftUI

extension FavoritePadsStore {
    func restore(_ entries: [FavoritePad], account: UUID, undoManager: UndoManager?, actionName: String) {
        let before = byAccount[account] ?? []
        // Anything the restore drops relative to the current list is a removal to
        // propagate; anything it (re-)introduces is stamped as freshly added so it
        // beats any remote tombstone (#738).
        let restoredIDs = Set(entries.map(\.id))
        for entry in before where !restoredIDs.contains(entry.id) {
            recordRemoval(of: entry.id, account: account)
        }
        // Only entries the restore actually brings back are restamped. Restamping
        // every entry made unrelated old favourites look newly added, so they beat
        // remote deletion tombstones and reappeared on other devices after an
        // undo that had nothing to do with them (#2527).
        let presentIDs = Set(before.map(\.id))
        let now = mutationTimestamp(account: account)
        byAccount[account] = entries.map { entry in
            guard !presentIDs.contains(entry.id) else { return entry }

            var entry = entry
            entry.addedAt = now
            return entry
        }
        save(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    func registerUndo(to entries: [FavoritePad], account: UUID, undoManager: UndoManager?,
                      actionName: String,
                      order: FavoritesOrderStore.OrderSnapshot? = nil) {
        guard let undoManager else { return }

        let affectedAccounts = Set((order?.merged.map(\.account) ?? []) + [account])
        let lifetime = AccountUndoLifetime.capture(affectedAccounts)
        undoManager.registerUndo(withTarget: self) { store in
            guard lifetime.isCurrent else { return }

            // Order first: `restore` re-adds the membership, and the sidebar
            // reconciles against whatever order is in place at that moment.
            if let order {
                FavoritesOrderStore.shared.restore(order, account: account)
            }
            store.restore(entries, account: account, undoManager: undoManager, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
