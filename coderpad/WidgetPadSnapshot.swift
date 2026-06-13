//
//  WidgetPadSnapshot.swift
//  coderpad
//
//  The data contract shared between the app and its widget extension. This file
//  must be a member of BOTH the `coderpad` app target (which writes snapshots) and
//  the `coderpadWidget` extension target (which reads them) — add the widget target
//  membership in the File inspector. It deliberately depends on nothing but
//  Foundation so it compiles cleanly in the lean widget process.
//
//  A widget runs in its own sandbox and cannot read the app's private cache, so the
//  app mirrors a small slice of the current account's recent pads into a shared App
//  Group container and the widget reads it back.
//

import Foundation

/// A minimal, dependency-free projection of a `Pad` for display in the widget.
nonisolated struct WidgetPadSnapshot: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let language: String?
    let updatedAt: Date?
}

/// A configurable account choice the widget can pin. Mirrored from the app's
/// account list so the widget's configuration picker can populate its options from
/// inside the widget process. Kept in lock-step with the widget's copy.
nonisolated struct WidgetAccount: Codable, Identifiable, Hashable, Sendable {
    /// The account's UUID, as a string so it round-trips the JSON contract and keys
    /// the per-account snapshot file.
    let id: String
    let name: String
}

/// Reads and writes the recent-pads snapshots in the App Group container shared by
/// the app and the widget. All members are `nonisolated` so the widget's timeline
/// provider can call them off the main actor.
///
/// The container holds one snapshot per account (`recent-pads-<id>.json`), a
/// default snapshot for the account currently on screen (`recent-pads.json`, read
/// by an unconfigured widget), and an account index (`widget-accounts.json`) that
/// backs the configuration picker.
nonisolated enum WidgetSharedStore {
    /// Shared container identifier. Declared in both targets' entitlements. If
    /// `containerURL` ever returns nil at runtime, this likely needs the team-id
    /// prefixed form (`6L9H6Q8CUF.group.ptn.coderpad`) on macOS.
    static let appGroupID = "group.ptn.coderpad"

    /// The widget's kind, shared so the app and widget agree on the identifier.
    static let widgetKind = "RecentPadsWidget"

    private static let defaultPadsFile = "recent-pads.json"
    private static let accountsFile = "widget-accounts.json"

    /// File holding `account`'s pads, or the default (current-account) snapshot when
    /// `account` is nil — the file an unconfigured widget reads.
    private static func padsFileName(account: String?) -> String {
        guard let account, !account.isEmpty else { return defaultPadsFile }
        return "recent-pads-\(account).json"
    }

    private static func fileURL(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: name, directoryHint: .notDirectory)
    }

    /// Pads for `account`, or the default snapshot when `account` is nil. Returns an
    /// empty list when the file is missing (e.g. a pinned account with nothing cached
    /// yet) rather than falling back to a different account's pads.
    static func load(account: String? = nil) -> [WidgetPadSnapshot] {
        guard let url = fileURL(padsFileName(account: account)),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetPadSnapshot].self, from: data)) ?? []
    }

    /// The mirrored account list backing the configuration picker, or empty when none
    /// has been written yet.
    static func loadAccounts() -> [WidgetAccount] {
        guard let url = fileURL(accountsFile), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([WidgetAccount].self, from: data)) ?? []
    }

    /// Atomically replaces `account`'s snapshot (or the default snapshot when nil). A
    /// no-op when the shared container is unavailable, so callers needn't guard the
    /// entitlement themselves.
    static func save(_ pads: [WidgetPadSnapshot], account: String? = nil) {
        guard let url = fileURL(padsFileName(account: account)),
              let data = try? JSONEncoder().encode(pads) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Atomically replaces the account index read by the configuration picker.
    static func saveAccounts(_ accounts: [WidgetAccount]) {
        guard let url = fileURL(accountsFile), let data = try? JSONEncoder().encode(accounts) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Removes a removed account's per-account snapshot so it stops lingering.
    static func deletePads(account: String) {
        guard let url = fileURL(padsFileName(account: account)) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
