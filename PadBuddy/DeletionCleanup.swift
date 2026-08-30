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
import os

@MainActor
enum DeletionCleanup {
    /// Held for the app's lifetime; the streams are not expected to finish, so the
    /// tasks are never explicitly cancelled. The handles are cleared if a stream does
    /// end, which is what lets `start()` rebuild the listener (#2352).
    private static var padTask: Task<Void, Never>?
    private static var questionTask: Task<Void, Never>?
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "deletion-cleanup")
    /// How often an account-less deletion checks whether the list caches finished
    /// warming before it is treated as genuinely unresolvable (#4609, #5150).
    private static let unresolvedRetryInterval = Duration.milliseconds(100)

    /// Retry only while at least one configured account still has an in-flight disk
    /// warm. There is deliberately no elapsed-time cutoff: a slow disk read remains
    /// capable of resolving the deletion once it completes (#5150).
    static func shouldRetryUnresolvedDeletion(cacheWarmInFlight: [Bool]) -> Bool {
        cacheWarmInFlight.contains(true)
    }

    /// Starts the process-wide listeners, and restarts either one that is no longer
    /// running. `start()` used to be gated on `padTask == nil` alone, so if a stream
    /// ever finished — leaving the task complete — nothing could recreate the missing
    /// listener, and every later deletion silently skipped its persistent cleanup
    /// (#2352). Calling this repeatedly is still safe: a live listener is left alone.
    static func start() {
        if padTask == nil {
            padTask = Task {
                for await deletion in AppRouter.padDeletions {
                    cleanUpDeletedPad(deletion)
                }
                // Reaching here means the stream finished, which is not expected for a
                // process-lifetime broadcast. Log it and drop the handle so the next
                // `start()` can rebuild the listener.
                logger.error("Pad deletion listener ended; cleanup is paused until it is restarted")
                padTask = nil
            }
        }
        if questionTask == nil {
            questionTask = Task {
                for await deletion in AppRouter.questionDeletions {
                    cleanUpDeletedQuestion(deletion)
                }
                logger.error("Question deletion listener ended; cleanup is paused until it is restarted")
                questionTask = nil
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
        guard let owner = deletion.account ?? soleCachedHolder(ofPad: deletion.id) else {
            // At cold launch the list caches are still being read from disk, so an early
            // account-less broadcast found no holder and was dropped for good — leaving
            // that pad's cache, favourites, Spotlight entry, and history behind (#4609).
            // Retrying while the caches fill costs nothing: every step below is idempotent.
            guard shouldRetryUnresolvedDeletion(cacheWarmInFlight:
                AccountsStore.shared.accounts.map { PadsCacheStore.shared.isPrewarming($0.id) })
            else {
                logger.info("Dropped an unresolvable pad deletion broadcast; no account owns it unambiguously")
                return
            }

            Task {
                do {
                    try await Task.sleep(for: unresolvedRetryInterval)
                } catch {
                    return
                }
                cleanUpDeletedPad(deletion)
            }
            return
        }
        guard PadsCacheStore.shared.removePad(
            id: deletion.id, account: owner, via: deletion.clientIdentity
        ) else {
            logger.info("Dropped a pad deletion from stale account credentials")
            return
        }

        // Keyed by the owning account id, so these run whether or not the account is
        // still configured. They used to sit behind the account lookup below, and an
        // account removed before its deletion broadcast arrived kept its pinned and
        // recently-opened entries for a pad that no longer exists (#2349).
        FavoritePadsStore.shared.remove(deletion.id, account: owner)
        PadOpenedStore.shared.removePad(deletion.id, account: owner)
        if let account = AccountsStore.shared.accounts.first(where: { $0.id == owner }) {
            // The detail cache is keyed by pad + client credentials, so the owning
            // account's client reaches its entry.
            PadDetailCacheStore.shared.remove(deletion.id, client: account.makeClient())
        } else {
            // With the account gone there is no client to key by, so every identity's
            // entry for this pad id goes (#2349). Removing an account already purges
            // its whole identity (#884); this covers the deletion arriving afterwards.
            PadDetailCacheStore.shared.removeAll(padID: deletion.id)
            logger.info("Cleaned up a pad deletion for an account that is no longer configured")
        }
    }

    /// The question counterpart: the list cache (which also updates Spotlight) and
    /// the starred-question entry (#722). Question deletions carry their owning
    /// account because per-org ids collide; a bare id applies only when exactly
    /// one account's cache holds it, mirroring the pad path (#1154).
    static func cleanUpDeletedQuestion(_ deletion: QuestionDeletion) {
        guard let owner = deletion.account ?? soleCachedHolder(ofQuestion: deletion.id) else {
            guard shouldRetryUnresolvedDeletion(cacheWarmInFlight:
                AccountsStore.shared.accounts.map {
                    QuestionsCacheStore.shared.isPrewarming($0.id)
                })
            else {
                logger.info("Dropped an unresolvable question deletion broadcast; no account owns it unambiguously")
                return
            }

            Task {
                do {
                    try await Task.sleep(for: unresolvedRetryInterval)
                } catch {
                    return
                }
                cleanUpDeletedQuestion(deletion)
            }
            return
        }
        guard QuestionsCacheStore.shared.removeQuestion(
            id: deletion.id, account: owner, via: deletion.clientIdentity
        ) else {
            logger.info("Dropped a question deletion from stale account credentials")
            return
        }

        FavoriteQuestionsStore.shared.remove(deletion.id, account: owner)
    }

    /// The one account whose cached pads contain `id`, or nil when none or
    /// several do (an ambiguous cross-server collision must not be swept).
    ///
    /// Reads only the resident lists. `get` falls back to a synchronous whole-file
    /// read and decode for every account not yet consulted — on the main actor, for
    /// each account-less deletion broadcast (#2078). That is the same reason the
    /// id-only cache sweeps stopped warming from disk (#2448), and launch prewarms
    /// every account's snapshot anyway (#1769), so ownership still resolves on a
    /// cold app. The scan stops at the second holder rather than filtering the whole
    /// account list, since two holders already mean the deletion is dropped.
    private static func soleCachedHolder(ofPad id: String) -> UUID? {
        var holder: UUID?
        for account in AccountsStore.shared.accounts
            where PadsCacheStore.shared.cached(account.id).contains(where: { $0.id == id }) {
            guard holder == nil else { return nil }

            holder = account.id
        }
        return holder
    }

    private static func soleCachedHolder(ofQuestion id: Int) -> UUID? {
        var holder: UUID?
        for account in AccountsStore.shared.accounts
            where QuestionsCacheStore.shared.cached(account.id).contains(where: { $0.id == id }) {
            guard holder == nil else { return nil }

            holder = account.id
        }
        return holder
    }
}
