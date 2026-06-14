//
//  AppRouter.swift
//  coderpad
//

import Foundation

/// A pad mutation broadcast: the updated question and the account that owns it.
/// The account travels with the payload because per-org question ids collide
/// across accounts, so combined-view consumers need it to scope the update.
struct QuestionMutation: Sendable {
    let question: Question
    let account: UUID?
}

/// A question deletion broadcast: the deleted question's id and its owning account
/// (see ``QuestionMutation`` for why the account is carried).
struct QuestionDeletion: Sendable {
    let id: Int
    let account: UUID?
}

/// Typed, app-wide router for cross-cutting commands (reload, open-settings, bulk
/// actions…) and data-change broadcasts (pad/question updated/deleted). It replaces
/// scattered `NotificationCenter.default.post(name:object:)` calls and
/// `note.object as?` downcasts: posting and observing both go through a single typed
/// surface, so payloads are checked at compile time and there are no silent failures
/// when an object's type doesn't match the listener's expectation.
///
/// It is deliberately a thin facade over `NotificationCenter`, keeping its proven
/// multicast delivery — each observer property hands back its own `AsyncStream`, so
/// several views can observe the same event independently, exactly as before. The
/// win is the typed API at every call site, not a new delivery mechanism.
@MainActor
enum AppRouter {
    private static let center = NotificationCenter.default

    // MARK: - Commands

    /// Ask every visible section to reload its data (the toolbar/⌘R Reload).
    static func requestReload() { center.post(name: .reloadRequested, object: nil) }
    static var reloads: AsyncStream<Void> { voidStream(.reloadRequested) }

    /// Ask the main window to present the "Open Pad by URL" sheet.
    static func requestOpenPadByURL() { center.post(name: .openPadByURLRequested, object: nil) }
    static var openPadByURLRequests: AsyncStream<Void> { voidStream(.openPadByURLRequested) }

    /// Ask the main window to open Settings.
    static func requestOpenSettings() { center.post(name: .openSettingsRequested, object: nil) }
    static var openSettingsRequests: AsyncStream<Void> { voidStream(.openSettingsRequested) }

    /// Ask the app to open `url` in a Pad Browser window.
    static func requestOpenPadInBrowser(_ url: URL) {
        center.post(name: .openPadInBrowserRequested, object: url)
    }
    static var openPadInBrowserRequests: AsyncStream<URL> {
        payloadStream(.openPadInBrowserRequested) { $0.object as? URL }
    }

    /// Ask the Pads list to run the "End all started pads" bulk action.
    static func requestBulkEndStarted() { center.post(name: .bulkEndStartedRequested, object: nil) }
    static var bulkEndStartedRequests: AsyncStream<Void> { voidStream(.bulkEndStartedRequested) }

    /// Ask the Pads list to run the "Make all pads private" bulk action.
    static func requestBulkMakePrivate() { center.post(name: .bulkMakePrivateRequested, object: nil) }
    static var bulkMakePrivateRequests: AsyncStream<Void> { voidStream(.bulkMakePrivateRequested) }

    // MARK: - Pad mutations

    /// Broadcast that a pad changed, so every list showing it updates in place.
    static func padUpdated(_ pad: Pad) { center.post(name: .padUpdated, object: pad) }
    static var padUpdates: AsyncStream<Pad> { payloadStream(.padUpdated) { $0.object as? Pad } }

    /// Broadcast that the pad with `id` was deleted, so lists drop the row.
    static func padDeleted(id: String) { center.post(name: .padDeleted, object: id) }
    static var padDeletions: AsyncStream<String> { payloadStream(.padDeleted) { $0.object as? String } }

    // MARK: - Question mutations

    /// Broadcast that a question changed. The owning `account` is carried so
    /// combined-view consumers can scope the update (per-org ids collide).
    static func questionUpdated(_ question: Question, account: UUID?) {
        center.post(name: .questionUpdated, object: question, userInfo: userInfo(account))
    }
    static var questionUpdates: AsyncStream<QuestionMutation> {
        payloadStream(.questionUpdated) { note in
            (note.object as? Question).map { QuestionMutation(question: $0, account: account(from: note)) }
        }
    }

    /// Broadcast that the question with `id` (owned by `account`) was deleted.
    static func questionDeleted(id: Int, account: UUID?) {
        center.post(name: .questionDeleted, object: id, userInfo: userInfo(account))
    }
    static var questionDeletions: AsyncStream<QuestionDeletion> {
        payloadStream(.questionDeleted) { note in
            (note.object as? Int).map { QuestionDeletion(id: $0, account: account(from: note)) }
        }
    }

    // MARK: - Plumbing

    /// Wraps a notification name in a fresh `AsyncStream` that yields each post,
    /// mapped through `transform` (posts that don't match are skipped). The inner
    /// observation task is cancelled when the consumer stops iterating, so each
    /// view's `.task { for await … }` cleans up exactly as the raw
    /// `notifications(named:)` loop did.
    private static func payloadStream<T: Sendable>(
        _ name: Notification.Name,
        _ transform: @escaping @Sendable (Notification) -> T?
    ) -> AsyncStream<T> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                for await note in center.notifications(named: name) {
                    if let value = transform(note) { continuation.yield(value) }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func voidStream(_ name: Notification.Name) -> AsyncStream<Void> {
        payloadStream(name) { _ in () }
    }

    private nonisolated static func userInfo(_ account: UUID?) -> [AnyHashable: Any]? {
        account.map { [accountUserInfoKey: $0] }
    }

    private nonisolated static func account(from note: Notification) -> UUID? {
        note.userInfo?[accountUserInfoKey] as? UUID
    }

    /// `userInfo` key carrying the owning account `UUID` on question broadcasts.
    private nonisolated static let accountUserInfoKey = "coderpad.account"
}

private extension Notification.Name {
    static let reloadRequested = Notification.Name("coderpad.reloadRequested")
    static let openPadByURLRequested = Notification.Name("coderpad.openPadByURLRequested")
    static let padUpdated = Notification.Name("coderpad.padUpdated")
    static let padDeleted = Notification.Name("coderpad.padDeleted")
    static let questionUpdated = Notification.Name("coderpad.questionUpdated")
    static let questionDeleted = Notification.Name("coderpad.questionDeleted")
    static let openSettingsRequested = Notification.Name("coderpad.openSettingsRequested")
    static let openPadInBrowserRequested = Notification.Name("coderpad.openPadInBrowserRequested")
    static let bulkEndStartedRequested = Notification.Name("coderpad.bulkEndStartedRequested")
    static let bulkMakePrivateRequested = Notification.Name("coderpad.bulkMakePrivateRequested")
}
