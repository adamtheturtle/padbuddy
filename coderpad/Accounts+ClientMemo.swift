//
//  Accounts+ClientMemo.swift
//  coderpad
//
//  The per-credentials memo behind `Account.makeClient()`.
//

import Foundation

/// Memoized `CoderPadClient`s, keyed by the credentials they are built from, so the
/// repeated `makeClient()` calls that happen during view-body evaluation reuse one
/// instance instead of building a fresh REST transport stack per render pass — the
/// section content rebuilt one on every keystroke routed through the active search
/// (#2111). The same shape as `Account.parsedTints` (#2464), for the same reason.
///
/// Keying on the credentials rather than the account id is what makes reuse safe: a
/// re-keyed or re-homed account simply misses and builds a fresh client, so no caller
/// can be handed a client for credentials the account no longer has. That pair is
/// already the identity the client-keyed caches use (see ``ClientCacheTeardown``), and
/// the live `URLSession` is a shared static, so a memoized client behaves exactly like
/// a freshly built one. Only stored accounts' credentials reach the memo, so it holds
/// one entry per account plus one per re-key in the session — it bounds itself in
/// practice, and a stale entry is simply unreachable once its credentials change.
///
/// `makeScreenClient()` deliberately isn't memoized: `ScreenClient` stores three
/// values and shares its session, so building one is already free.
@MainActor
enum ClientMemo {
    /// The inputs `makeClient()` builds from: the trimmed key plus the resolved
    /// server for a real account, or a nil server and the 401 flag for the in-process
    /// mock, whose server is fixed.
    struct Recipe: Hashable {
        let apiKey: String
        let baseURL: URL?
        let isUnauthorizedMock: Bool
    }

    private static var clients: [Recipe: CoderPadClient] = [:]

    /// The memoized client for `recipe`, building and storing one on a miss.
    static func client(_ recipe: Recipe, build: () -> CoderPadClient) -> CoderPadClient {
        if let cached = clients[recipe] { return cached }

        let client = build()
        clients[recipe] = client
        return client
    }

    /// How many clients are currently memoized, so tests can prove reuse.
    static var count: Int {
        clients.count
    }

    /// Empties the memo, so tests can start from a known state. The app never needs
    /// to: an entry can only be reused by an account that still has exactly those
    /// credentials.
    static func removeAll() {
        clients.removeAll()
    }
}
