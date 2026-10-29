//
//  WidgetPadSnapshot.swift
//  coderpad
//
//  The app's side of the data contract shared with the widget extension: it writes
//  the snapshots the widget reads. The `coderpad` and `RecentPadsWidget` folders are
//  synchronized to their own targets, so this is NOT compiled into the extension —
//  the widget has a parallel reader in `RecentPadsWidget/WidgetSharedSnapshot.swift`,
//  and the two must be kept in lock-step. The value types both sides encode live in
//  WidgetSharedTypes.swift.
//
//  A widget runs in its own sandbox and cannot read the app's private cache, so the
//  app mirrors a small slice of the current account's recent pads into a shared App
//  Group container and the widget reads it back.
//

import Foundation
import OSLog

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
    /// Several members below are internal rather than private because the handoff
    /// request half of this store lives in WidgetHandoffRequests.swift, split out to
    /// keep both files under the file-length limit.
    /// Shared container identifier. iOS/iPadOS only supports the provisioned `group.`
    /// form. Non-App-Store macOS keeps the Team-ID-prefixed form to avoid requiring a
    /// provisioning profile (#451).
    static let appGroupID: String = {
        #if os(macOS) && !APP_STORE
            "6L9H6Q8CUF.group.com.adamdangoor.padbuddy"
        #else
            "group.com.adamdangoor.padbuddy"
        #endif
    }()

    private static let defaultPadsFile = "recent-pads.json"
    private static let accountsFile = "widget-accounts.json"
    static let padsFilePrefix = "recent-pads-"
    static let favoritesFilePrefix = "widget-favorites-"
    static let logger = Logger(subsystem: "com.coderpad.app", category: "widget-shared-store")

    /// One coder each for the whole store, rather than one per read or write.
    /// `loadSnapshot` runs on every timeline refresh and the configuration queries
    /// read the account index and favourites per query, so a fresh coder was being
    /// allocated and thrown away on each of them (#2135). Both types are stateless
    /// once configured — nothing here mutates their options — so one shared instance
    /// behaves identically. `nonisolated(unsafe)` because these are read from
    /// whichever thread the widget or the app's write queue happens to be on.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    /// File holding `account`'s pads, or the default (current-account) snapshot when
    /// `account` is nil — the file an unconfigured widget reads.
    /// An account identifier reduced to characters that cannot alter a path.
    ///
    /// These identifiers are account UUID strings in practice, but the API takes a
    /// `String`, so a malformed caller value containing a separator or `..` would have
    /// escaped the per-account naming scheme and written outside it (#2184). Anything
    /// unexpected is folded to "-", which at worst collides two odd identifiers onto
    /// one file rather than letting either reach a path it should not.
    static func fileSafeAccount(_ account: String) -> String {
        String(account.map { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
                ? character
                : "-"
        })
    }

    private static func padsFileName(account: String?) -> String {
        guard let account, !account.isEmpty else { return defaultPadsFile }

        return "recent-pads-\(fileSafeAccount(account)).json"
    }

    /// File holding `account`'s favourite questions, for the New Pad button picker.
    private static func favoritesFileName(account: String) -> String {
        "widget-favorites-\(fileSafeAccount(account)).json"
    }

    static func containerURL(purpose: String) -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            logger.error("Widget shared container unavailable for \(purpose, privacy: .public)")
            return nil
        }

        return container
    }

    private static func fileURL(_ name: String, purpose: String) -> URL? {
        guard let container = containerURL(purpose: purpose) else { return nil }

        return container.appending(path: name, directoryHint: .notDirectory)
    }

    @discardableResult
    static func save(_ value: some Encodable, fileName: String, purpose: String) -> Bool {
        guard let url = fileURL(fileName, purpose: purpose) else { return false }

        return save(value, to: url, purpose: purpose)
    }

    @discardableResult
    static func save(_ value: some Encodable, to url: URL, purpose: String) -> Bool {
        do {
            let data = try encoder.encode(value)
            guard data.count <= maxSnapshotFileBytes else {
                logger.error("Widget shared store refused an oversized \(purpose, privacy: .public) write")
                return false
            }

            try data.write(to: url, options: writeOptions)
            return true
        } catch EncodingError.invalidValue(_, _) {
            logger.error("Widget shared store encode failed for \(purpose, privacy: .public)")
        } catch {
            logger.error("""
            Widget shared store write failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .private)
            """)
        }
        return false
    }

    /// Atomic, and — on iOS — protected until the device is first unlocked.
    ///
    /// These files hold pad titles and favourite-question titles, and the writes took
    /// the platform default, which on iOS leaves them readable while the device is
    /// locked (#2600). `.completeUntilFirstUserAuthentication` rather than
    /// `.complete`: a widget's timeline is rebuilt in the background well after the
    /// user last unlocked, and `.complete` would make those reads fail and blank the
    /// widget. macOS has no file-protection classes, so it keeps the plain atomic
    /// write; the container there is already inside the user's sandboxed home.
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.atomic]
        #endif
    }

    private static func remove(_ fileName: String, purpose: String) {
        guard let url = fileURL(fileName, purpose: purpose) else { return }

        remove(url: url, purpose: purpose)
    }

    private static func remove(url: URL, purpose: String) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            logger.error("""
            Widget shared store remove failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .private)
            """)
        }
    }

    /// Atomically replaces `account`'s snapshot (or the default snapshot when nil). A
    /// no-op when the shared container is unavailable, so callers needn't guard the
    /// entitlement themselves.
    static func save(_ pads: [WidgetPadSnapshot], account: String? = nil) {
        save(pads, fileName: padsFileName(account: account), purpose: "recent pads snapshot")
    }

    /// Atomically replaces the account index read by the configuration picker.
    static func saveAccounts(_ accounts: [WidgetAccount]) {
        // De-duplicated by id: the widget's configuration picker keys its options on
        // this, so a repeated id produced two indistinguishable rows and an ambiguous
        // stored choice (#2185).
        var seen = Set<String>()
        let unique = accounts.filter { seen.insert($0.id).inserted }
        save(unique, fileName: accountsFile, purpose: "widget account index")
    }

    /// The most favourites written for one account.
    ///
    /// The whole list used to be serialized, so a large organization bloated the App
    /// Group and slowed every widget configuration and read (#2186). The picker shows
    /// a bounded list anyway, and favourites are already in the user's chosen order,
    /// so the ones beyond this cap were never reachable from the widget.
    static let maxStoredFavorites = 200

    /// Atomically replaces `account`'s favourite-questions list.
    static func saveFavorites(_ favorites: [WidgetQuestion], account: String) {
        save(Array(favorites.prefix(maxStoredFavorites)),
             fileName: favoritesFileName(account: account),
             purpose: "widget favorite questions")
    }

    /// Moves UUID-keyed files written by older versions onto the stable widget id.
    /// Existing stable files win, making this safe to repeat at every account sync.
    static func migrateAccountFiles(from legacyAccount: String, to stableAccount: String) {
        migrateFile(from: padsFileName(account: legacyAccount), to: padsFileName(account: stableAccount),
                    purpose: "recent pads identity migration")
        migrateFile(from: favoritesFileName(account: legacyAccount), to: favoritesFileName(account: stableAccount),
                    purpose: "favorite questions identity migration")
    }

    private static func migrateFile(from sourceName: String, to destinationName: String, purpose: String) {
        guard sourceName != destinationName,
              let source = fileURL(sourceName, purpose: purpose),
              let destination = fileURL(destinationName, purpose: purpose),
              FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: destination.path) else { return }

        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            logger.error("Widget shared store migration failed for \(purpose, privacy: .public)")
        }
    }

    /// Removes a removed account's per-account snapshot and favourites so they stop
    /// lingering.
    static func deletePads(account: String) {
        remove(padsFileName(account: account), purpose: "account recent pads snapshot")
        remove(favoritesFileName(account: account), purpose: "account favorite questions")
        // Queued handoffs naming this account outlived it, so a later drain routed a
        // create or open against an account that no longer exists (#2187).
        if !discardPendingRequests(account: account) {
            logger.error("Some widget requests could not be finalized during account cleanup")
        }
    }
}
