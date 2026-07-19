//
//  AppRouter.swift
//  coderpad
//

import Foundation
import os
import SwiftUI

/// A pad mutation broadcast: the updated pad and the account that owns it. Pad
/// slugs are unique on the hosted service, but independent custom servers can
/// issue colliding slugs, so consumers scope to the account when one is known
/// (#761); a nil account falls back to the old slug-only matching.
struct PadMutation {
    let pad: Pad
    let account: UUID?
}

/// A pad deletion broadcast: the deleted pad's slug and its owning account
/// (see ``PadMutation`` for why the account is carried).
struct PadDeletion {
    let id: String
    let account: UUID?
    let clientIdentity: ClientTaskIdentity
}

/// A question mutation broadcast: the updated question and the account that owns
/// it. The account travels with the payload because per-org question ids collide
/// across accounts, so combined-view consumers need it to scope the update.
struct QuestionMutation {
    let question: Question
    let account: UUID?
}

/// A question deletion broadcast: the deleted question's id and its owning account
/// (see ``QuestionMutation`` for why the account is carried).
struct QuestionDeletion {
    let id: Int
    let account: UUID?
    let clientIdentity: ClientTaskIdentity
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
    static func requestReload() {
        center.post(name: .reloadRequested, object: nil)
    }

    static var reloads: AsyncStream<Void> {
        voidStream(.reloadRequested)
    }

    /// Ask the main window to present the "Open Pad by URL" sheet.
    static func requestOpenPadByURL() {
        center.post(name: .openPadByURLRequested, object: nil)
    }

    static var openPadByURLRequests: AsyncStream<Void> {
        voidStream(.openPadByURLRequested)
    }

    /// Ask the main window to present the command palette (Cmd-K, #526).
    static func requestCommandPalette() {
        center.post(name: .commandPaletteRequested, object: nil)
    }

    static var commandPaletteRequests: AsyncStream<Void> {
        voidStream(.commandPaletteRequested)
    }

    // MARK: - Pad mutations

    /// Broadcast that a pad changed, so every list showing it updates in place.
    /// The owning `account` is carried so consumers can scope the update: custom
    /// servers can issue colliding slugs across accounts (#761).
    static func padUpdated(_ pad: Pad, account: UUID?) {
        center.post(name: .padUpdated, object: pad, userInfo: userInfo(account))
    }

    static var padUpdates: AsyncStream<PadMutation> {
        payloadStream(.padUpdated) { note in
            (note.object as? Pad).map { PadMutation(pad: $0, account: account(from: note)) }
        }
    }

    /// Broadcast that a pad was just created outside the list views — the widget /
    /// Control Center path, the menu-bar extra, and "New Pad from Question" — so
    /// every mounted list inserts the row immediately instead of leaving it
    /// invisible until the next full reload (#1251).
    static func padCreated(_ pad: Pad, account: UUID?) {
        center.post(name: .padCreated, object: pad, userInfo: userInfo(account))
    }

    static var padCreations: AsyncStream<PadMutation> {
        payloadStream(.padCreated) { note in
            (note.object as? Pad).map { PadMutation(pad: $0, account: account(from: note)) }
        }
    }

    /// Broadcast that the pad with `id` (owned by `account`) was deleted, so
    /// lists drop the row.
    static func padDeleted(id: String, account: UUID?, via client: CoderPadClient) {
        var info = userInfo(account) ?? [:]
        info[clientIdentityUserInfoKey] = client.taskIdentity
        center.post(name: .padDeleted, object: id, userInfo: info)
    }

    static var padDeletions: AsyncStream<PadDeletion> {
        payloadStream(.padDeleted) { note in
            guard let id = note.object as? String,
                  let identity = note.userInfo?[clientIdentityUserInfoKey] as? ClientTaskIdentity else { return nil }

            return PadDeletion(id: id, account: account(from: note), clientIdentity: identity)
        }
    }

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
    static func questionDeleted(id: Int, account: UUID?, via client: CoderPadClient) {
        var info = userInfo(account) ?? [:]
        info[clientIdentityUserInfoKey] = client.taskIdentity
        center.post(name: .questionDeleted, object: id, userInfo: info)
    }

    static var questionDeletions: AsyncStream<QuestionDeletion> {
        payloadStream(.questionDeleted) { note in
            guard let id = note.object as? Int,
                  let identity = note.userInfo?[clientIdentityUserInfoKey] as? ClientTaskIdentity else { return nil }

            return QuestionDeletion(id: id, account: account(from: note), clientIdentity: identity)
        }
    }

    // MARK: - Plumbing

    /// Wraps a notification name in a fresh `AsyncStream` that yields each post,
    /// mapped through `transform` (posts that don't match are skipped). The inner
    /// observation task is cancelled when the consumer stops iterating, so each
    /// view's `.task { for await … }` cleans up exactly as the raw
    /// `notifications(named:)` loop did.
    /// Carries a `NotificationCenter` observer token across the `@Sendable`
    /// termination boundary. The token is opaque here — it is only ever passed back to
    /// `removeObserver` on the main actor — so the unchecked conformance is safe.
    /// Diagnostics for broadcasts that never reach a consumer.
    private nonisolated static let routerLogger = Logger(subsystem: "com.coderpad.app", category: "app-router")

    private final class ObserverToken: @unchecked Sendable {
        let value: any NSObjectProtocol

        init(_ value: any NSObjectProtocol) {
            self.value = value
        }
    }

    private static func payloadStream<T: Sendable>(
        _ name: Notification.Name,
        _ transform: @escaping @Sendable (Notification) -> T?
    ) -> AsyncStream<T> {
        // Bounded buffering: a slow or suspended consumer under a high mutation
        // rate must not accumulate an unbounded in-memory queue (#1826). Keeping
        // the newest events is correct for this router's payloads — they carry
        // current record state, and consumers reconcile via reloads anyway.
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            // The observer is registered here, synchronously, rather than inside a
            // `Task`. `center.notifications(named:)` only starts observing once its
            // task is scheduled, so anything posted between creating the stream and
            // that first suspension was dropped — exactly the window a view hits when
            // it mounts and immediately triggers a mutation (#2682).
            let token = ObserverToken(center.addObserver(forName: name, object: nil, queue: nil) { note in
                guard let value = transform(note) else {
                    // A post whose payload isn't the shape this stream expects is a
                    // producer bug: the consumer simply never updates, which shows up
                    // as unexplained stale UI with nothing to trace it to (#2705).
                    let payload = String(describing: type(of: note.object))
                    routerLogger.error(
                        """
                        Discarded a malformed \(name.rawValue, privacy: .public) broadcast; \
                        payload was \(payload, privacy: .public)
                        """
                    )
                    return
                }

                continuation.yield(value)
            })
            // `onTermination` is `@Sendable` and runs off the main actor, so the
            // removal hops back; the token only ever crosses the boundary as an opaque
            // value handed straight to `removeObserver`.
            continuation.onTermination = { _ in
                Task { @MainActor in center.removeObserver(token.value) }
            }
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

    /// `userInfo` key carrying the owning account `UUID` on mutation broadcasts.
    private nonisolated static let accountUserInfoKey = "coderpad.account"
    private nonisolated static let clientIdentityUserInfoKey = "coderpad.client-identity"
}

private extension Notification.Name {
    static let reloadRequested = Notification.Name("coderpad.reloadRequested")
    static let openPadByURLRequested = Notification.Name("coderpad.openPadByURLRequested")
    static let commandPaletteRequested = Notification.Name("coderpad.commandPaletteRequested")
    static let padUpdated = Notification.Name("coderpad.padUpdated")
    static let padCreated = Notification.Name("coderpad.padCreated")
    static let padDeleted = Notification.Name("coderpad.padDeleted")
    static let questionUpdated = Notification.Name("coderpad.questionUpdated")
    static let questionDeleted = Notification.Name("coderpad.questionDeleted")
}

/// Consumes an `AppRouter` broadcast only while this view's window is focused.
/// The router's commands are process-wide notifications, so without this every
/// window acted on them at once: ⌘R reloaded every mounted list in every window
/// (#905), and Open Pad by URL / the command palette presented their UI in every
/// main window simultaneously (#906). The focused-window state is tracked through
/// a reference box because the long-running consumption task would otherwise
/// capture a stale `controlActiveState` snapshot from one body evaluation.
/// `controlActiveState` doesn't exist on iOS, where `scenePhase` gives the same
/// signal: only the scene the user is in reports `.active` (#2685).
@MainActor
final class RouterWindowFocus {
    /// An unmounted window has not established focus and must not consume a
    /// process-wide request before its environment is sampled (#2062).
    var isFocused = false
}

private struct FocusedWindowRequestModifier: ViewModifier {
    #if os(macOS)
        @Environment(\.controlActiveState) private var controlActiveState
    #else
        @Environment(\.scenePhase) private var scenePhase
    #endif
    @State private var focus = RouterWindowFocus()
    let stream: () -> AsyncStream<Void>
    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        focusTracking(content)
        #if os(macOS)
            .onAppear { focus.isFocused = controlActiveState != .inactive }
            .onChange(of: controlActiveState) { _, state in focus.isFocused = state != .inactive }
        #else
            // `controlActiveState` is macOS-only, so every iOS scene used to count as
            // focused — and in iPad multi-window a reload or palette request was then
            // handled by all of them at once (#2685). `scenePhase` is the equivalent
            // signal: only the scene the user is in reports `.active`.
            .onAppear { focus.isFocused = scenePhase == .active }
            .onChange(of: scenePhase) { _, phase in focus.isFocused = phase == .active }
        #endif
    }

    private func focusTracking(_ content: Content) -> some View {
        content.task { [focus] in
            for await _ in stream() where focus.isFocused {
                await action()
            }
        }
    }
}

extension View {
    /// Runs `action` for an `AppRouter` void broadcast, but only while this view's
    /// window is the focused one (#905, #906).
    func onFocusedWindowRequest(_ stream: @escaping () -> AsyncStream<Void>,
                                perform action: @escaping @MainActor () async -> Void) -> some View {
        modifier(FocusedWindowRequestModifier(stream: stream, action: action))
    }

    /// Reload-on-⌘R scoped to the focused window (#905).
    func onReloadRequest(perform action: @escaping @MainActor () async -> Void) -> some View {
        onFocusedWindowRequest({ AppRouter.reloads }, perform: action)
    }
}
