//
//  Accounts+FavoriteQuestions+Undo.swift
//  coderpad
//
//  Undo/restore for FavoriteQuestionsStore, split from
//  Accounts+FavoriteQuestions.swift to keep that file within the length lint.
//

import Foundation

extension FavoriteQuestionsStore {
    func restore(_ entries: [FavoriteQuestion], account: UUID, undoManager: UndoManager?, actionName: String) {
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
        // remote deletion tombstones and reappeared on other devices after an undo
        // that had nothing to do with them (#2527).
        let presentIDs = Set(before.map(\.id))
        let now = Date()
        byAccount[account] = entries.map { entry in
            guard !presentIDs.contains(entry.id) else { return entry }

            var entry = entry
            entry.addedAt = now
            return entry
        }
        save()
        WidgetSync.syncFavorites(account: account)
        registerUndo(to: before, account: account, undoManager: undoManager, actionName: actionName)
    }

    func registerUndo(to entries: [FavoriteQuestion], account: UUID,
                      undoManager: UndoManager?, actionName: String,
                      order: FavoritesOrderStore.OrderSnapshot? = nil) {
        guard let undoManager else { return }

        undoManager.registerUndo(withTarget: self) { store in
            // Order first: `restore` re-adds the membership, and the sidebar
            // reconciles against whatever order is in place at that moment.
            if let order { FavoritesOrderStore.shared.restore(order, account: account) }
            store.restore(entries, account: account, undoManager: undoManager, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }
}
