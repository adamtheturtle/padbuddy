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
            for await deletion in AppRouter.padDeletions {
                cleanUpDeletedPad(deletion)
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
    /// With a known owning account (slugs can collide across custom servers, #761)
    /// only that account's state is cleared. An account-less broadcast resolves
    /// against the cached lists and applies only when exactly one account holds
    /// the slug: sweeping every account removed account B's pins and activity
    /// state for account A's same-slug delete (#1154). Ambiguous or unresolvable
    /// legacy events are dropped.
    static func cleanUpDeletedPad(_ deletion: PadDeletion) {
        guard let owner = deletion.account ?? soleCachedHolder(ofPad: deletion.id) else { return }

        PadsCacheStore.shared.removePad(id: deletion.id, account: owner)
        guard let account = AccountsStore.shared.accounts.first(where: { $0.id == owner }) else { return }

        FavoritePadsStore.shared.remove(deletion.id, account: account.id)
        PadOpenedStore.shared.removePad(deletion.id, account: account.id)
        // The detail cache is keyed by pad + client credentials, so the owning
        // account's client reaches its entry.
        PadDetailCacheStore.shared.remove(deletion.id, client: account.makeClient())
    }

    /// The question counterpart: the list cache (which also updates Spotlight) and
    /// the starred-question entry (#722). Question deletions carry their owning
    /// account because per-org ids collide; a bare id applies only when exactly
    /// one account's cache holds it, mirroring the pad path (#1154).
    static func cleanUpDeletedQuestion(_ deletion: QuestionDeletion) {
        guard let owner = deletion.account ?? soleCachedHolder(ofQuestion: deletion.id) else { return }

        QuestionsCacheStore.shared.removeQuestion(id: deletion.id, account: owner)
        FavoriteQuestionsStore.shared.remove(deletion.id, account: owner)
    }

    /// The one account whose cached pads contain `id`, or nil when none or
    /// several do (an ambiguous cross-server collision must not be swept).
    private static func soleCachedHolder(ofPad id: String) -> UUID? {
        let holders = AccountsStore.shared.accounts.filter { account in
            PadsCacheStore.shared.get(account.id).contains { $0.id == id }
        }
        return holders.count == 1 ? holders.first?.id : nil
    }

    private static func soleCachedHolder(ofQuestion id: Int) -> UUID? {
        let holders = AccountsStore.shared.accounts.filter { account in
            QuestionsCacheStore.shared.get(account.id).contains { $0.id == id }
        }
        return holders.count == 1 ? holders.first?.id : nil
    }
}
