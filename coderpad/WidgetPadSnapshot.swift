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
    static let newPadRequestFile = "pending-new-pad.json"
    static let openPadRequestFile = "pending-open-pad.json"
    static let newPadRequestPrefix = "pending-new-pad-"
    static let openPadRequestPrefix = "pending-open-pad-"
    static let requestFileExtension = ".json"
    static let newPadPurpose = "new pad handoff request"
    static let openPadPurpose = "open pad handoff request"
    /// Log label for the one listing that covers both request kinds (#2138).
    static let pendingRequestsPurpose = "pending handoff requests"
    static let claimedRequestPrefix = "claimed-"
    static let corruptRequestPrefix = "corrupt-"
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
    nonisolated(unsafe) static let encoder = JSONEncoder()
    nonisolated(unsafe) static let decoder = JSONDecoder()

    /// Darwin notification posted when a New Pad request is recorded, so a running app
    /// drains it immediately — even while it's already frontmost, where a widget/control
    /// tap triggers no activation and so `applicationDidBecomeActive` never fires (#485).
    /// A global Darwin name, prefixed with the App Group id for uniqueness. Must match
    /// the widget target's copy (`RecentPadsWidget/WidgetSharedSnapshot.swift`).
    static let newPadRequestNotification = "\(appGroupID).new-pad-requested"

    /// Darwin notification posted when an iPad/iPhone widget recent-pad tap records an
    /// Open Pad request. Mirrors `newPadRequestNotification` for the separate request file.
    static let openPadRequestNotification = "\(appGroupID).open-pad-requested"

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

    static func requestFileName(prefix: String) -> String {
        // Zero-padded to a fixed width so lexical filename order is ordinal order;
        // the UUID only keeps two files from colliding, it no longer decides order.
        let ordinal = String(format: "%018llu", nextRequestOrdinal())
        return "\(prefix)\(ordinal)-\(UUID().uuidString)\(requestFileExtension)"
    }

    /// A strictly increasing ordinal for the next request file, zero-padded so the
    /// filenames sort lexically in issue order.
    ///
    /// Ordering used to come from `Date()` alone, with a random UUID breaking ties.
    /// Two actions in the same millisecond therefore replayed in UUID order rather
    /// than the order the user took them (#2590), and a clock change or skew between
    /// the app, widget, and extension processes could make an older request sort
    /// after a newer one (#2591) — both contradicting the newest-action-wins
    /// behaviour the drain relies on.
    ///
    /// The ordinal starts from the wall clock, so unrelated drains still produce
    /// sensible values, but is then forced above every ordinal already pending in
    /// the container. Ordering only has to hold among requests that are pending at
    /// the same time, and this makes it hold regardless of what the clock does.
    static func nextRequestOrdinal() -> UInt64 {
        let now = UInt64(max(0, Date().timeIntervalSince1970 * 1000))
        guard let container = containerURL(purpose: "handoff request ordinal"),
              let names = try? FileManager.default
              .contentsOfDirectory(at: container, includingPropertiesForKeys: nil)
              .map(\.lastPathComponent)
        else { return now }

        let highest = names
            .compactMap { name -> UInt64? in
                guard name.hasPrefix(newPadRequestPrefix) || name.hasPrefix(openPadRequestPrefix) else {
                    return nil
                }

                return requestOrdinal(fileName: name)
            }
            .max() ?? 0
        return max(now, highest + 1)
    }

    /// The ordinal embedded in a request filename, or 0 for the legacy fixed-name
    /// files (which predate ordering and sort first, as the oldest).
    static func requestOrdinal(fileName: String) -> UInt64 {
        // Strip the known prefix rather than scanning to the first "-": the prefixes
        // themselves contain hyphens ("pending-new-pad-"), so splitting on one lands
        // inside the prefix and finds no digits at all.
        let remainder: Substring
        if fileName.hasPrefix(newPadRequestPrefix) {
            remainder = fileName.dropFirst(newPadRequestPrefix.count)
        } else if fileName.hasPrefix(openPadRequestPrefix) {
            remainder = fileName.dropFirst(openPadRequestPrefix.count)
        } else {
            return 0
        }
        return UInt64(remainder.prefix(while: \.isNumber)) ?? 0
    }

    @discardableResult
    static func save(_ value: some Encodable, fileName: String, purpose: String) -> Bool {
        guard let url = fileURL(fileName, purpose: purpose) else { return false }

        do {
            let data = try encoder.encode(value)
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

    private static func loadData(fileName: String, purpose: String) -> Data? {
        guard let url = fileURL(fileName, purpose: purpose) else { return nil }

        return loadData(url: url, purpose: purpose)
    }

    static func loadData(url: URL, purpose: String) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("""
            Widget shared store read failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .private)
            """)
            return nil
        }
    }

    /// The millisecond timestamp embedded in a request filename, used to order a
    /// combined drain across both request kinds (#1045). The legacy fixed-name files
    /// predate any timestamped request, so they sort first as 0.
    private static func requestTimestamp(fileName: String) -> Int64 {
        for prefix in [newPadRequestPrefix, openPadRequestPrefix] where fileName.hasPrefix(prefix) {
            return Int64(fileName.dropFirst(prefix.count).prefix(while: \.isNumber)) ?? 0
        }
        return 0
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

    /// Claims a request file by atomically renaming it to a unique path, returning
    /// the claimed URL. Rename-to-claim gives exactly-once consumption two ways: a
    /// request is only executed by the process that won the rename (#779), and a
    /// concurrent writer replacing the legacy fixed-name file either lands before the
    /// claim (its newer bytes are the ones read) or after (its file survives for the
    /// next drain) - whereas read-then-delete could execute stale bytes while
    /// unlinking a newer write (#752).
    static func claim(url: URL, purpose: String) -> URL? {
        let claimed = url.deletingLastPathComponent()
            .appendingPathComponent("claimed-\(UUID().uuidString).json")
        do {
            try FileManager.default.moveItem(at: url, to: claimed)
            return claimed
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return nil
        } catch {
            logger.error("""
            Widget shared store claim failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .private)
            """)
            return nil
        }
    }

    /// Claims, decodes, and deletes a single request file. Nil when another process
    /// won the claim race or when the payload fails to decode.
    static func takeRequest<Request: Decodable>(
        at url: URL,
        purpose: String,
        as type: Request.Type
    ) -> Request? {
        guard let claimedURL = claim(url: url, purpose: purpose) else { return nil }
        guard let data = loadData(url: claimedURL, purpose: purpose) else {
            try? FileManager.default.removeItem(at: claimedURL)
            return nil
        }

        do {
            let request = try decoder.decode(type, from: data)
            try? FileManager.default.removeItem(at: claimedURL)
            return request
        } catch {
            // Quarantine rather than delete. Deleting threw away the user's action
            // with no trace and no way to tell a corrupt payload from one that was
            // never recorded (#2593). The file is renamed out of the drain's way so
            // it is not retried forever, and the retention sweep clears it later.
            let quarantined = claimedURL.deletingLastPathComponent()
                .appendingPathComponent("\(corruptRequestPrefix)\(UUID().uuidString).json")
            try? FileManager.default.moveItem(at: claimedURL, to: quarantined)
            logger.error("""
            Widget shared store decode failed for \(purpose, privacy: .public), quarantined: \
            \(error.localizedDescription, privacy: .private)
            """)
            return nil
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

    /// Removes a removed account's per-account snapshot and favourites so they stop
    /// lingering.
    static func deletePads(account: String) {
        remove(padsFileName(account: account), purpose: "account recent pads snapshot")
        remove(favoritesFileName(account: account), purpose: "account favorite questions")
        // Queued handoffs naming this account outlived it, so a later drain routed a
        // create or open against an account that no longer exists (#2187).
        discardPendingRequests(account: account)
    }
}
