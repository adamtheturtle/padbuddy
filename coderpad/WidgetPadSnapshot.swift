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

/// A pending "create a new pad" request the widget/Control Center New Pad button
/// records for the app to perform on its next activation (the widget can't open the
/// app's custom URL scheme, #456/#485). Kept in lock-step with the widget's copy.
nonisolated struct WidgetNewPadRequest: Codable {
    let account: String?
    let question: Int?
}

/// A pending "open an existing pad" request the iPad widget records for the app to
/// perform on its next activation (custom-scheme widget links are unreliable there,
/// #660). Kept in lock-step with the widget's copy.
nonisolated struct WidgetOpenPadRequest: Codable {
    let id: String
    let account: String?
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
    /// Shared container identifier. The App Store build uses the provisioned `group.`
    /// form; Developer ID keeps the Team-ID-prefixed form to avoid requiring a
    /// provisioning profile (#451).
    static let appGroupID: String = {
        #if APP_STORE
            "group.com.adamdangoor.padbuddy"
        #else
            "6L9H6Q8CUF.group.com.adamdangoor.padbuddy"
        #endif
    }()

    private static let defaultPadsFile = "recent-pads.json"
    private static let accountsFile = "widget-accounts.json"
    private static let newPadRequestFile = "pending-new-pad.json"
    private static let openPadRequestFile = "pending-open-pad.json"

    /// Darwin notification posted when a New Pad request is recorded, so a running app
    /// drains it immediately — even while it's already frontmost, where a widget/control
    /// tap triggers no activation and so `applicationDidBecomeActive` never fires (#485).
    /// A global Darwin name, prefixed with the App Group id for uniqueness. Must match
    /// the widget target's copy (`RecentPadsWidget/WidgetSharedSnapshot.swift`).
    static let newPadRequestNotification = "\(appGroupID).new-pad-requested"

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

    /// Records a New Pad request for the app to pick up on its next activation, written
    /// as a file (not `UserDefaults`) so it's seen immediately across the App Group with
    /// no suite-cache delay. Idempotent — `takePendingNewPad` is the single consumer and
    /// deletes the file, so re-recording the same request before consumption is harmless.
    /// A no-op when the container is unavailable. Mirrors the widget target's copy
    /// (`RecentPadsWidget/WidgetSharedSnapshot.swift`); it lives here too so the app-target
    /// twin of `CreatePadIntent` — the one that lets the Control Center button open the
    /// app (#485) — compiles against it.
    static func requestNewPad(account: String?, question: Int?) {
        guard let url = fileURL(newPadRequestFile),
              let data = try? JSONEncoder().encode(WidgetNewPadRequest(account: account, question: question))
        else { return }

        try? data.write(to: url, options: .atomic)
        postNewPadRequestNotification()
    }

    /// Records an iPad widget recent-pad tap for the app to route after the intent opens it.
    static func requestOpenPad(id: String, account: String?) {
        guard let url = fileURL(openPadRequestFile),
              let data = try? JSONEncoder().encode(WidgetOpenPadRequest(id: id, account: account))
        else { return }

        try? data.write(to: url, options: .atomic)
    }

    /// Nudges a running app to drain the just-recorded request right away.
    /// `applicationDidBecomeActive` covers cold launch and background→foreground, but
    /// not the case where the app is already frontmost (a control/widget tap then causes
    /// no activation transition), so post a Darwin notification the app observes to drain
    /// regardless of its activation state (#485). Cross-process and payload-free by design.
    private static func postNewPadRequestNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(newPadRequestNotification as CFString),
            nil, nil, true
        )
    }

    /// Returns and clears any pending New Pad request the widget/Control Center button
    /// recorded, so the app performs it once on activation. Nil when none is pending.
    static func takePendingNewPad() -> WidgetNewPadRequest? {
        guard let url = fileURL(newPadRequestFile), let data = try? Data(contentsOf: url) else { return nil }

        try? FileManager.default.removeItem(at: url)
        return try? JSONDecoder().decode(WidgetNewPadRequest.self, from: data)
    }

    /// Returns and clears any pending iPad widget request to open an existing pad.
    static func takePendingOpenPad() -> WidgetOpenPadRequest? {
        guard let url = fileURL(openPadRequestFile), let data = try? Data(contentsOf: url) else { return nil }

        try? FileManager.default.removeItem(at: url)
        return try? JSONDecoder().decode(WidgetOpenPadRequest.self, from: data)
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
