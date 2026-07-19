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
    private static let newPadRequestFile = "pending-new-pad.json"
    private static let openPadRequestFile = "pending-open-pad.json"
    private static let newPadRequestPrefix = "pending-new-pad-"
    private static let openPadRequestPrefix = "pending-open-pad-"
    private static let requestFileExtension = ".json"
    private static let newPadPurpose = "new pad handoff request"
    private static let openPadPurpose = "open pad handoff request"
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "widget-shared-store")

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
    private static func padsFileName(account: String?) -> String {
        guard let account, !account.isEmpty else { return defaultPadsFile }

        return "recent-pads-\(account).json"
    }

    /// File holding `account`'s favourite questions, for the New Pad button picker.
    private static func favoritesFileName(account: String) -> String {
        "widget-favorites-\(account).json"
    }

    private static func containerURL(purpose: String) -> URL? {
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

    private static func requestFileName(prefix: String) -> String {
        let milliseconds = Int64(Date().timeIntervalSince1970 * 1000)
        return "\(prefix)\(milliseconds)-\(UUID().uuidString)\(requestFileExtension)"
    }

    @discardableResult
    private static func save(_ value: some Encodable, fileName: String, purpose: String) -> Bool {
        guard let url = fileURL(fileName, purpose: purpose) else { return false }

        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: writeOptions)
            return true
        } catch EncodingError.invalidValue(_, _) {
            logger.error("Widget shared store encode failed for \(purpose, privacy: .public)")
        } catch {
            logger.error("""
            Widget shared store write failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
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

    private static func loadData(url: URL, purpose: String) -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            logger.error("""
            Widget shared store read failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
            return nil
        }
    }

    private static func pendingRequestURLs(legacyFileName: String, prefix: String, purpose: String) -> [URL] {
        guard let container = containerURL(purpose: purpose) else { return [] }

        do {
            return try FileManager.default
                .contentsOfDirectory(at: container, includingPropertiesForKeys: nil)
                .filter { url in
                    let name = url.lastPathComponent
                    return name == legacyFileName || (name.hasPrefix(prefix) && name.hasSuffix(requestFileExtension))
                }
        } catch {
            logger.error("""
            Widget shared store list failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
            return []
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
            \(error.localizedDescription, privacy: .public)
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
    private static func claim(url: URL, purpose: String) -> URL? {
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
            \(error.localizedDescription, privacy: .public)
            """)
            return nil
        }
    }

    /// Claims, decodes, and deletes a single request file. Nil when another process
    /// won the claim race or when the payload fails to decode.
    private static func takeRequest<Request: Decodable>(
        at url: URL,
        purpose: String,
        as type: Request.Type
    ) -> Request? {
        guard let claimedURL = claim(url: url, purpose: purpose) else { return nil }

        defer { try? FileManager.default.removeItem(at: claimedURL) }
        guard let data = loadData(url: claimedURL, purpose: purpose) else { return nil }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("""
            Widget shared store decode failed for \(purpose, privacy: .public): \
            \(error.localizedDescription, privacy: .public)
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
        save(accounts, fileName: accountsFile, purpose: "widget account index")
    }

    /// Atomically replaces `account`'s favourite-questions list.
    static func saveFavorites(_ favorites: [WidgetQuestion], account: String) {
        save(favorites, fileName: favoritesFileName(account: account), purpose: "widget favorite questions")
    }

    /// Records a New Pad request for the app to pick up on its next activation, written
    /// as a file (not `UserDefaults`) so it's seen immediately across the App Group with
    /// no suite-cache delay. Idempotent: `takePendingRequestsInOrder` is the single
    /// consumer and deletes the file, so re-recording before consumption is harmless.
    /// A no-op when the container is unavailable. Mirrors the widget target's copy
    /// (`RecentPadsWidget/WidgetSharedSnapshot.swift`); it lives here too so the app-target
    /// twin of `CreatePadIntent` — the one that lets the Control Center button open the
    /// app (#485) — compiles against it.
    @discardableResult
    static func requestNewPad(account: String?, question: Int?) -> Bool {
        guard save(WidgetNewPadRequest(account: account, question: question),
                   fileName: requestFileName(prefix: newPadRequestPrefix),
                   purpose: newPadPurpose) else {
            return false
        }

        postNewPadRequestNotification()
        logger.info("""
        Recorded new pad handoff request accountScoped=\((account?.isEmpty == false), privacy: .public) \
        questionSeeded=\(question != nil, privacy: .public)
        """)
        return true
    }

    /// Records an iPad widget recent-pad tap for the app to route after the intent opens it.
    @discardableResult
    static func requestOpenPad(id: String, account: String?) -> Bool {
        guard save(WidgetOpenPadRequest(id: id, account: account),
                   fileName: requestFileName(prefix: openPadRequestPrefix),
                   purpose: openPadPurpose) else {
            return false
        }

        postOpenPadRequestNotification()
        logger.info("Recorded open pad handoff request accountScoped=\((account?.isEmpty == false), privacy: .public)")
        return true
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

    private static func postOpenPadRequestNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(openPadRequestNotification as CFString),
            nil, nil, true
        )
    }

    /// Returns and clears every pending widget/Shortcuts request, of both kinds, in
    /// the order the user issued them. The request filenames embed a millisecond
    /// timestamp, so a single combined drain can replay them chronologically and the
    /// user's most recent action ends up on top (#1045). Empty when none is pending.
    static func takePendingRequestsInOrder() -> [WidgetPendingRequest] {
        let candidates = pendingRequestURLs(
            legacyFileName: newPadRequestFile, prefix: newPadRequestPrefix, purpose: newPadPurpose
        ).map { (url: $0, isNewPad: true) } + pendingRequestURLs(
            legacyFileName: openPadRequestFile, prefix: openPadRequestPrefix, purpose: openPadPurpose
        ).map { (url: $0, isNewPad: false) }

        let requests: [WidgetPendingRequest] = candidates
            .sorted {
                (requestTimestamp(fileName: $0.url.lastPathComponent), $0.url.lastPathComponent)
                    < (requestTimestamp(fileName: $1.url.lastPathComponent), $1.url.lastPathComponent)
            }
            .compactMap { candidate in
                if candidate.isNewPad {
                    return takeRequest(at: candidate.url, purpose: newPadPurpose, as: WidgetNewPadRequest.self)
                        .map(WidgetPendingRequest.newPad)
                }
                return takeRequest(at: candidate.url, purpose: openPadPurpose, as: WidgetOpenPadRequest.self)
                    .map(WidgetPendingRequest.openPad)
            }
        if !requests.isEmpty {
            logger.info("Drained \(requests.count, privacy: .public) pending widget requests in order")
        }
        return requests
    }

    /// Removes a removed account's per-account snapshot and favourites so they stop
    /// lingering.
    static func deletePads(account: String) {
        remove(padsFileName(account: account), purpose: "account recent pads snapshot")
        remove(favoritesFileName(account: account), purpose: "account favorite questions")
    }
}
