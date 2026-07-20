//
//  WidgetSharedSnapshot.swift
//  RecentPadsWidget
//
//  The widget side of the data contract shared with the app. The app writes recent
//  pads into the App Group container (see the app's `WidgetPadSnapshot.swift` /
//  `WidgetSync.swift`); this reads them back. The two definitions are deliberately
//  kept in lock-step on the JSON shape (property names) rather than sharing a file,
//  so the widget target stays free of any app dependency.
//

import Foundation
import OSLog

/// A minimal, dependency-free projection of a pad for display in the widget.
struct WidgetPadSnapshot: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let language: String?
    let updatedAt: Date?
}

struct WidgetPadSnapshotLoad {
    let pads: [WidgetPadSnapshot]
}

/// A configurable account choice. Mirrored from the app's account list (kept in
/// lock-step with the app's copy) so the configuration picker can populate its
/// options from inside the widget process.
struct WidgetAccount: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let legacyID: String?
}

/// A favourite question the New Pad button can seed a pad from. Mirrored per
/// account; kept in lock-step with the app's copy.
struct WidgetQuestion: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
}

/// A pending "create a new pad" request the widget's New Pad button records for the
/// app to perform when it next activates. Used instead of a deep link because
/// `OpenURLIntent` can't open the app's custom URL scheme and `Link` is ignored on
/// the small widget family, so an interactive `Button` + this hand-off is the only
/// thing that works on every family (#456). Kept in lock-step with the app's copy.
struct WidgetNewPadRequest: Codable {
    let id: UUID
    /// The account UUID string to switch to first (nil for the current account), and
    /// the favourite question id to seed the create sheet with (nil for a blank pad).
    let account: String?
    let question: Int?

    init(account: String?, question: Int?, id: UUID = UUID()) {
        self.id = id
        self.account = account
        self.question = question
    }

    private enum CodingKeys: String, CodingKey {
        case id, account, question
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        account = try values.decodeIfPresent(String.self, forKey: .account)
        question = try values.decodeIfPresent(Int.self, forKey: .question)
    }
}

/// A pending "open an existing pad" request the iPad widget records for the app to
/// perform when it next activates. Recent-pad taps use this instead of a custom-scheme
/// `Link` on iPadOS, where the widget can show the link affordance without delivering
/// the URL to the app reliably (#660). Kept in lock-step with the app's copy.
struct WidgetOpenPadRequest: Codable {
    let id: String
    let account: String?
}

/// Reads the recent-pads snapshots from the App Group container shared with the app.
/// The app writes one snapshot per account (`recent-pads-<id>.json`), a default
/// snapshot for the current account (`recent-pads.json`), and the account index
/// (`widget-accounts.json`); this reads them back.
enum WidgetSharedStore {
    /// Must match the app's `WidgetSharedStore.appGroupID`. iOS/iPadOS only supports
    /// the provisioned `group.` form. Non-App-Store macOS keeps the Team-ID-prefixed
    /// form to avoid requiring a provisioning profile (#451).
    static let appGroupID: String = {
        #if os(macOS) && !APP_STORE
            "6L9H6Q8CUF.group.com.adamdangoor.padbuddy"
        #else
            "group.com.adamdangoor.padbuddy"
        #endif
    }()

    /// The widget's kind, shared with the app's reload logic.
    static let widgetKind = "RecentPadsWidget"

    private static let defaultPadsFile = "recent-pads.json"
    private static let accountsFile = "widget-accounts.json"
    private static let newPadRequestFile = "pending-new-pad.json"
    private static let openPadRequestFile = "pending-open-pad.json"
    static let newPadRequestPrefix = "pending-new-pad-"
    static let openPadRequestPrefix = "pending-open-pad-"
    static let requestFileExtension = ".json"
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "widget-shared-store")

    /// One coder each for the whole store, rather than one per read or write.
    /// `loadSnapshot` runs on every timeline refresh and the configuration queries
    /// read the account index and favourites per query, so a fresh coder was being
    /// allocated and thrown away on each of them (#2135). Both types are stateless
    /// once configured — nothing here mutates their options — so one shared instance
    /// behaves identically. `nonisolated(unsafe)` because these are read from
    /// whichever thread the widget or the app's write queue happens to be on.
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Darwin notification posted when a New Pad request is recorded, so a running app
    /// drains it immediately — even while it's already frontmost, where a widget/control
    /// tap triggers no activation and so `applicationDidBecomeActive` never fires (#485).
    /// A global Darwin name, prefixed with the App Group id for uniqueness. Must match
    /// the app target's copy (`coderpad/WidgetPadSnapshot.swift`).
    static let newPadRequestNotification = "\(appGroupID).new-pad-requested"

    /// Darwin notification posted when an iPad/iPhone widget recent-pad tap records an
    /// Open Pad request. Mirrors `newPadRequestNotification` for the separate request file.
    static let openPadRequestNotification = "\(appGroupID).open-pad-requested"

    /// File holding `account`'s pads, or the default (current-account) snapshot when
    /// `account` is nil.
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

    /// File holding `account`'s favourite questions.
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

    private static func requestFileName(prefix: String) -> String {
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
    private static func nextRequestOrdinal() -> UInt64 {
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

    private static func loadData(fileName: String, purpose: String) -> Data? {
        guard let url = fileURL(fileName, purpose: purpose) else { return nil }

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

    /// Matches the app side's protection class (see the app's `WidgetSharedStore`):
    /// the handoff requests this side writes name a pad and an account, so they get
    /// the same treatment as the snapshots (#2600).
    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
            [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
            [.atomic]
        #endif
    }

    @discardableResult
    private static func write(_ value: some Encodable, fileName: String, purpose: String) -> Bool {
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

    /// Pads for the configured `account`, or the default snapshot when `account` is
    /// nil. Empty when the file is missing.
    static func load(account: String? = nil) -> [WidgetPadSnapshot] {
        loadSnapshot(account: account).pads
    }

    /// Pads from the app-written snapshot for `account`, or the default snapshot when
    /// no account is pinned.
    static func loadSnapshot(account: String? = nil) -> WidgetPadSnapshotLoad {
        guard let data = loadData(fileName: padsFileName(account: account), purpose: "recent pads snapshot") else {
            return WidgetPadSnapshotLoad(pads: [])
        }

        do {
            let pads = try decoder.decode([WidgetPadSnapshot].self, from: data)
            return WidgetPadSnapshotLoad(pads: pads)
        } catch {
            logger.error("""
            Widget shared store decode failed for recent pads snapshot: \
            \(error.localizedDescription, privacy: .private)
            """)
            return WidgetPadSnapshotLoad(pads: [])
        }
    }

    /// The mirrored account list backing the configuration picker.
    static func loadAccounts() -> [WidgetAccount] {
        guard let data = loadData(fileName: accountsFile, purpose: "widget account index") else { return [] }

        do {
            return try decoder.decode([WidgetAccount].self, from: data)
        } catch {
            logger.error("""
            Widget shared store decode failed for account index: \
            \(error.localizedDescription, privacy: .private)
            """)
            return []
        }
    }

    /// `account`'s mirrored favourite questions, for the New Pad button picker.
    static func loadFavorites(account: String) -> [WidgetQuestion] {
        loadFavorites(accounts: [account])[account] ?? []
    }

    /// Mirrored favourite questions for several accounts, decoded with the shared
    /// decoder so widget configuration queries don't allocate one per account (#2292).
    static func loadFavorites(accounts: [String]) -> [String: [WidgetQuestion]] {
        guard !accounts.isEmpty else { return [:] }

        var favorites: [String: [WidgetQuestion]] = [:]
        for account in accounts {
            guard let data = loadData(
                fileName: favoritesFileName(account: account),
                purpose: "widget favorite questions"
            ) else {
                favorites[account] = []
                continue
            }

            do {
                favorites[account] = try decoder.decode([WidgetQuestion].self, from: data)
            } catch {
                logger.error("""
                Widget shared store decode failed for favorite questions: \
                \(error.localizedDescription, privacy: .private)
                """)
                favorites[account] = []
            }
        }
        return favorites
    }

    /// The widest pad id worth queueing. Real ids are short slugs; anything longer can
    /// only be malformed configuration, and persisting it just fills the App Group with
    /// a request nothing can route (#2364).
    static var maxHandoffPadIDLength: Int {
        64
    }

    /// Mirrors the app's PadIDValidation at this cross-target boundary.
    static func validatedHandoffPadID(_ id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1 ... maxHandoffPadIDLength).contains(trimmed.count),
              trimmed.allSatisfy({ character in
                  character == "-" || character == "_"
                      || (character.isASCII && (character.isLetter || character.isNumber))
              }) else { return nil }

        return trimmed
    }

    /// `.some(nil)` for a request that names no account (create in whichever is
    /// current), `.some(id)` for a well-formed one, and nil when the string is present
    /// but is not an account identifier — which the caller refuses outright (#2364).
    static func validatedAccount(_ account: String?) -> String?? {
        guard let account else { return .some(nil) }

        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .some(nil) }
        if let uuid = UUID(uuidString: trimmed) { return .some(uuid.uuidString) }
        guard trimmed.count == 64, trimmed.allSatisfy(\.isHexDigit) else { return nil }

        return .some(trimmed.lowercased())
    }

    /// Records a New Pad request for the app to pick up on its next activation. Written
    /// as a file (not `UserDefaults`) so the app process sees it immediately across the
    /// App Group, with no suite-cache delay. A no-op when the container is unavailable.
    @discardableResult
    static func requestNewPad(account: String?, question: Int?, requestID: UUID = UUID()) -> Bool {
        // CoderPad question ids are positive. A zero or negative one can only have
        // come from malformed configuration, and seeding the create flow with it
        // produces a request the server rejects, so drop the seed and let the flow
        // open unseeded rather than failing (#2595).
        let seed = question.flatMap { $0 > 0 ? $0 : nil }
        if question != nil, seed == nil {
            logger.error("Dropped a non-positive question seed from a new pad handoff request")
        }
        // The account travels as a string, so a stale or hand-edited configuration can
        // carry something that is not an account id at all. It used to be persisted and
        // only rejected at the far end, where the request was silently dropped; refusing
        // it here means an unusable request is never queued (#2364). A seed is scoped to
        // its account, so it cannot outlive one that failed to parse.
        guard let owner = validatedAccount(account) else {
            logger.error("Refused a new pad handoff request with a malformed account identifier")
            return false
        }

        if hasPendingNewPadRequest(requestID) { return true }

        reservePendingRequestSlot()
        guard write(WidgetNewPadRequest(account: owner, question: owner == nil ? nil : seed, id: requestID),
                    fileName: requestFileName(prefix: newPadRequestPrefix),
                    purpose: "new pad handoff request") else {
            return false
        }

        postNewPadRequestNotification()
        logger.info("""
        Recorded new pad handoff request accountScoped=\((account?.isEmpty == false), privacy: .public) \
        questionSeeded=\(question != nil, privacy: .public)
        """)
        return true
    }

    private static func hasPendingNewPadRequest(_ id: UUID) -> Bool {
        guard let container = containerURL(purpose: "new pad handoff request deduplication"),
              let urls = try? FileManager.default.contentsOfDirectory(
                  at: container,
                  includingPropertiesForKeys: [.isRegularFileKey]
              )
        else { return false }

        return urls.contains { url in
            guard url.lastPathComponent.hasPrefix(newPadRequestPrefix),
                  url.pathExtension == "json",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
                  let data = try? Data(contentsOf: url),
                  let request = try? decoder.decode(WidgetNewPadRequest.self, from: data)
            else { return false }

            return request.id == id
        }
    }

    /// Records a recent-pad tap for the iPad app to route after `OpenPadIntent` opens it.
    @discardableResult
    static func requestOpenPad(id: String, account: String?) -> Bool {
        // An empty id can only produce a handoff the app cannot act on: it would be
        // drained, consumed, and silently do nothing, with no way for the user to
        // retry (#2594). Refuse it at the source instead.
        guard let padID = validatedHandoffPadID(id) else {
            logger.error("Refused an open pad handoff request with an empty or malformed pad id")
            return false
        }
        guard let owner = validatedAccount(account) else {
            logger.error("Refused an open pad handoff request with a malformed account identifier")
            return false
        }

        reservePendingRequestSlot()
        guard write(WidgetOpenPadRequest(id: padID, account: owner),
                    fileName: requestFileName(prefix: openPadRequestPrefix),
                    purpose: "open pad handoff request") else {
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
}

// MARK: - Display helpers

extension WidgetPadSnapshot {
    /// A human-friendly language name (e.g. "JavaScript"), or `nil` when the pad has
    /// no language. Mirrors the app's `languageDisplayName`.
    var languageLabel: String? {
        guard let language, !language.isEmpty else { return nil }

        return language.languageDisplayName
    }

    /// A short relative description of the last update, e.g. "2 hr. ago". `nil` when no
    /// timestamp is available. Computed at render time, so the widget refreshes
    /// periodically (see the timeline provider) to keep it from going stale.
    var relativeUpdated: String? {
        guard let updatedAt else { return nil }

        return updatedAt.formatted(Self.relativeStyle)
    }

    /// Built once rather than per access. The style is read for every visible pad, for
    /// both its label and its VoiceOver description, and again for each row-count
    /// candidate the layout measures, so constructing it each time added up across a
    /// render (#2136).
    private static let relativeStyle = Date.RelativeFormatStyle(presentation: .numeric,
                                                                unitsStyle: .abbreviated)

    /// A single spoken label combining title, language, and last update for VoiceOver.
    var accessibilityDescription: String {
        accessibilityDescription(relativeUpdated: relativeUpdated)
    }

    /// The spoken label with the relative date supplied by the caller, for a view that
    /// has already formatted it for display and would otherwise format it again
    /// (#2136).
    func accessibilityDescription(relativeUpdated: String?) -> String {
        var parts = [title]
        if let languageLabel { parts.append(languageLabel) }
        if let relativeUpdated { parts.append("updated \(relativeUpdated)") }
        return parts.joined(separator: ", ")
    }
}

extension String {
    /// Friendly casing for CoderPad language codes. Duplicated from the app's
    /// `DesignSystem` extension so the widget target stays dependency-free.
    var languageDisplayName: String {
        // Bound once: the default branch lowercased the same string a second time, so
        // every unmatched code did the walk twice per widget entry render (#2457).
        let lowered = lowercased()
        switch lowered {
        case "python": return "Python"
        case "python2": return "Python 2"
        case "python3": return "Python 3"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "node", "node.js", "nodejs": return "Node.js"
        case "swift": return "Swift"
        case "go", "golang": return "Go"
        case "rust": return "Rust"
        case "java": return "Java"
        case "kotlin": return "Kotlin"
        case "ruby": return "Ruby"
        case "c": return "C"
        case "cpp", "c++": return "C++"
        case "csharp", "c#": return "C#"
        case "objective-c", "objc": return "Objective-C"
        case "php": return "PHP"
        case "html": return "HTML"
        case "css": return "CSS"
        case "sql": return "SQL"
        case "mysql": return "MySQL"
        case "postgresql", "postgres": return "PostgreSQL"
        case "bash": return "Bash"
        case "shell", "sh": return "Shell"
        case "r": return "R"
        case "scala": return "Scala"
        case "elixir": return "Elixir"
        case "erlang": return "Erlang"
        case "haskell": return "Haskell"
        case "perl": return "Perl"
        case "lua": return "Lua"
        case "dart": return "Dart"
        case "clojure": return "Clojure"
        case "ocaml": return "OCaml"
        case "f#", "fsharp": return "F#"
        case "plaintext", "plain-text", "plain_text": return "Plain text"
        default:
            if lowered.hasPrefix("multifile_") {
                let base = String(lowered.dropFirst("multifile_".count))
                return base.isEmpty ? "Project" : base.languageDisplayName + " Project"
            }
            guard !isEmpty else { return self }

            return prefix(1).uppercased() + dropFirst()
        }
    }
}
