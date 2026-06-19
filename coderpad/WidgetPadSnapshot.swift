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
nonisolated struct WidgetPadSnapshot: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let language: String?
    let updatedAt: Date?
}

/// A configurable account choice the widget can pin. Mirrored from the app's
/// account list so the widget's configuration picker can populate its options from
/// inside the widget process. Kept in lock-step with the widget's copy.
nonisolated struct WidgetAccount: Codable, Identifiable, Hashable {
    /// The account's UUID, as a string so it round-trips the JSON contract and keys
    /// the per-account snapshot file.
    let id: String
    let name: String
}

/// A favourite question the New Pad widget button can be configured to seed a new
/// pad from. Mirrored per account so the configuration picker can list a pinned
/// account's favourites from inside the widget process. Kept in lock-step with the
/// widget's copy.
nonisolated struct WidgetQuestion: Codable, Identifiable, Hashable {
    /// CoderPad's per-org question id. Not unique across accounts, so the new-pad
    /// deep link always carries the owning account alongside it.
    let id: Int
    let title: String
}

/// Writes the recent-pads snapshots into the App Group container shared with the
/// widget (the widget reads them back through its own parallel `WidgetSharedStore`
/// in `RecentPadsWidget/WidgetSharedSnapshot.swift`). All members are `nonisolated`
/// so they can be called off the main actor.
///
/// The container holds one snapshot per account (`recent-pads-<id>.json`), a
/// default snapshot for the account currently on screen (`recent-pads.json`, read
/// by an unconfigured widget), and an account index (`widget-accounts.json`) that
/// backs the configuration picker.
nonisolated enum WidgetSharedStore {
    /// Shared container identifier. Declared in both targets' entitlements. Uses the
    /// team-ID-prefixed form so notarized Developer-ID builds (no provisioning profile)
    /// are authorized for the App Group without the per-launch access prompt (#451).
    static let appGroupID = "6L9H6Q8CUF.group.com.adamdangoor.coderpad"

    private static let defaultPadsFile = "recent-pads.json"
    private static let accountsFile = "widget-accounts.json"

    /// File holding `account`'s pads, or the default (current-account) snapshot when
    /// `account` is nil — the file an unconfigured widget reads.
    private static func padsFileName(account: String?) -> String {
        guard let account, !account.isEmpty else { return defaultPadsFile }

        return "recent-pads-\(account).json"
    }

    /// File holding `account`'s favourite questions, for the New Pad button picker.
    private static func favoritesFileName(account: String) -> String {
        "widget-favorites-\(account).json"
    }

    private static func fileURL(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: name, directoryHint: .notDirectory)
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

    /// Atomically replaces `account`'s favourite-questions list.
    static func saveFavorites(_ favorites: [WidgetQuestion], account: String) {
        guard let url = fileURL(favoritesFileName(account: account)),
              let data = try? JSONEncoder().encode(favorites) else { return }

        try? data.write(to: url, options: .atomic)
    }

    /// Removes a removed account's per-account snapshot and favourites so they stop
    /// lingering.
    static func deletePads(account: String) {
        if let url = fileURL(padsFileName(account: account)) {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = fileURL(favoritesFileName(account: account)) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
