//
//  DeletionCleanup.swift
//  coderpad
//
//  Central cleanup for pad/question deletion broadcasts. List views used to own
//  the persistent cleanup in their notification listeners, so deleting from a
//  standalone detail window while no list was mounted left disk caches, Spotlight,
//  favorites, and open-history stale (#721). This process-lifetime listener runs
//  regardless of view lifecycle; views still react to the same events, but only
//  for their own visual state. Every operation here is idempotent, so a list
//  view's own cache cleanup running alongside is harmless.
//

import Foundation

@MainActor
enum DeletionCleanup {
    /// Held for the app's lifetime; the streams never finish, so the tasks are
    /// never explicitly cancelled.
    private static var padTask: Task<Void, Never>?
    private static var questionTask: Task<Void, Never>?

    /// Starts the process-wide listeners. Called once from `AppLaunch.run()`;
    /// subsequent calls are no-ops.
    static func start() {
        guard padTask == nil else { return }

        padTask = Task {
            for await id in AppRouter.padDeletions {
                cleanUpDeletedPad(id: id)
            }
        }
        questionTask = Task {
            for await deletion in AppRouter.questionDeletions {
                cleanUpDeletedQuestion(deletion)
            }
        }
    }

    /// Everything persisted or indexed under a deleted pad's id: the disk/memory
    /// list cache (which also updates Spotlight, the widget snapshot, and the Dock
    /// badge), the favorites entry (#722), the open-history timestamp (#723), and
    /// the in-memory detail cache holding its event log and code (#719).
    ///
    /// Pad deletion broadcasts carry no account (pad slugs are unique across the
    /// hosted service), so per-account state is cleared for every configured
    /// account - matching `PadsCacheStore.removePad`, which also scans them all.
    static func cleanUpDeletedPad(id: String) {
        PadsCacheStore.shared.removePad(id: id)
        for account in AccountsStore.shared.accounts {
            FavoritePadsStore.shared.remove(id, account: account.id)
            PadOpenedStore.shared.removePad(id, account: account.id)
            // The detail cache is keyed by pad + client credentials; every client
            // the app uses comes from an account, so this reaches every entry.
            PadDetailCacheStore.shared.remove(id, client: account.makeClient())
        }
    }

    /// The question counterpart: the list cache (which also updates Spotlight) and
    /// the starred-question entry (#722). Question deletions carry their owning
    /// account because per-org ids collide; without one, every account is swept.
    static func cleanUpDeletedQuestion(_ deletion: QuestionDeletion) {
        QuestionsCacheStore.shared.removeQuestion(id: deletion.id, account: deletion.account)
        if let account = deletion.account {
            FavoriteQuestionsStore.shared.remove(deletion.id, account: account)
        } else {
            for account in AccountsStore.shared.accounts {
                FavoriteQuestionsStore.shared.remove(deletion.id, account: account.id)
            }
        }
    }
}
