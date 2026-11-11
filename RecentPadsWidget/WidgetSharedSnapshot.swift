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

// swiftlint:disable file_length

import AppGroupMailbox
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
    let lastUpdated: Date?
    var accessUnavailable = false
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
struct WidgetNewPadRequest: Codable, Sendable {
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
struct WidgetOpenPadRequest: Codable, Sendable {
    let id: String
    let account: String?
}

enum WidgetPendingRequest: Codable, Sendable {
    case newPad(WidgetNewPadRequest)
    case openPad(WidgetOpenPadRequest)
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
    static let logger = Logger(subsystem: "com.coderpad.app", category: "widget-shared-store")

    /// Reuse the decoder across timeline refreshes and configuration queries.
    private static let decoder = JSONDecoder()

    static let handoffRequestNotification = "\(appGroupID).handoff-request-enqueued"

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

    private static func loadData(fileName: String, purpose: String) -> Data? {
        switch loadResult(fileName: fileName, purpose: purpose) {
        case let .data(data): data
        case .absent, .unreadable: nil
        }
    }

    private static func loadResult(fileName: String, purpose: String) -> WidgetDataLoad {
        // No container at all is itself unreadable access, not an absent file.
        guard let url = fileURL(fileName, purpose: purpose) else { return .unreadable }

        return loadResult(at: url, purpose: purpose)
    }

    /// Pads from the app-written snapshot for `account`, or the default snapshot when
    /// no account is pinned.
    /// The app writes at most this many pads per account (`WidgetSync.maxPads`).
    static let maxReadPads = 8
    /// The app stores at most this many favourites per account.
    static let maxReadFavorites = 200
    /// Longest title or subtitle a row will render before it is trimmed.
    static let maxReadTitleCharacters = 200

    static func loadSnapshot(account: String? = nil) -> WidgetPadSnapshotLoad {
        let fileName = padsFileName(account: account)
        let data: Data
        switch loadResult(fileName: fileName, purpose: "recent pads snapshot") {
        case let .data(value):
            data = value

        case .absent:
            return WidgetPadSnapshotLoad(pads: [], lastUpdated: nil)

        // Reported rather than guessed at from an empty account index (#4771).
        case .unreadable:
            return WidgetPadSnapshotLoad(pads: [], lastUpdated: nil, accessUnavailable: true)
        }

        do {
            // Bounded and de-duplicated on the way in, matching what the app bounds on the
            // way out. The container is shared, so a stale file from an older build or a
            // partially-written one could otherwise produce duplicate SwiftUI identities
            // and unbounded rows (#4769).
            let decoded = try decoder.decode([WidgetPadSnapshot].self, from: data)
            let pads = boundedPads(decoded)
            guard decoded.isEmpty || !pads.isEmpty else {
                return WidgetPadSnapshotLoad(pads: [], lastUpdated: nil, accessUnavailable: true)
            }

            let updated: Date?
            if let url = fileURL(fileName, purpose: "recent pads timestamp") {
                switch WidgetSnapshotMetadata.modificationDate(at: url) {
                case let .date(value):
                    updated = value
                case let .failed(message):
                    logger.error("\(message, privacy: .public)")
                    updated = nil
                }
            } else {
                updated = nil
            }
            return WidgetPadSnapshotLoad(pads: pads, lastUpdated: updated)
        } catch {
            logger.error("""
            Widget shared store decode failed for recent pads snapshot: \
            \(error.localizedDescription, privacy: .private)
            """)
            return WidgetPadSnapshotLoad(pads: [], lastUpdated: nil, accessUnavailable: true)
        }
    }

    /// The mirrored account list backing the configuration picker.
    static func loadAccounts() -> [WidgetAccount] {
        guard let data = loadData(fileName: accountsFile, purpose: "widget account index") else { return [] }

        do {
            // De-duplicated by id, as `saveAccounts` does: "a repeated id produced two
            // indistinguishable rows and an ambiguous stored choice" (#2185, #4769).
            return try boundedAccounts(decoder.decode([WidgetAccount].self, from: data))
        } catch {
            logger.error("""
            Widget shared store decode failed for account index: \
            \(error.localizedDescription, privacy: .private)
            """)
            return []
        }
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
        if trimmed.isEmpty {
            return .some(nil)
        }
        if let uuid = UUID(uuidString: trimmed) {
            return .some(uuid.uuidString)
        }
        guard trimmed.count == 64, trimmed.allSatisfy(\.isHexDigit) else { return nil }

        return .some(trimmed.lowercased())
    }

    @discardableResult
    static func requestNewPad(account: String?, question: Int?, requestID: UUID = UUID()) -> Bool {
        guard let request = validatedNewPadRequest(account: account, question: question, requestID: requestID) else {
            logger.error("Refused a new pad handoff request with an invalid account or question seed")
            return false
        }
        guard let mailbox = handoffMailbox() else { return false }

        do {
            try mailbox.enqueue(.newPad(request), id: requestID)
            return true
        } catch {
            logger.error(
                "Could not enqueue a new pad handoff request: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    @discardableResult
    static func requestOpenPad(id: String, account: String?) -> Bool {
        guard let padID = validatedHandoffPadID(id) else {
            logger.error("Refused an open pad handoff request with an empty or malformed pad id")
            return false
        }
        guard let owner = validatedAccount(account) else {
            logger.error("Refused an open pad handoff request with a malformed account identifier")
            return false
        }
        guard let mailbox = handoffMailbox() else { return false }

        do {
            try mailbox.enqueue(.openPad(WidgetOpenPadRequest(id: padID, account: owner)))
            return true
        } catch {
            logger.error(
                "Could not enqueue an open pad handoff request: \(error.localizedDescription, privacy: .private)"
            )
            return false
        }
    }

    private static func handoffMailbox() -> AppGroupMailbox<WidgetPendingRequest>? {
        guard let container = containerURL(purpose: "widget handoff mailbox") else { return nil }

        return try? AppGroupMailbox(
            containerURL: container,
            namespace: "widget-actions",
            limits: .init(
                maxMessages: 100,
                maxPayloadBytes: 65536,
                messageLifetime: 24 * 60 * 60,
                claimTimeout: 10 * 60,
                maxQuarantinedFiles: 20
            ),
            overflowPolicy: .discardOldest,
            notificationName: handoffRequestNotification
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
        if let languageLabel {
            parts.append(languageLabel)
        }
        if let relativeUpdated {
            parts.append(String(localized: "Updated \(relativeUpdated)"))
        }
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

/// Configuration queries must distinguish unavailable shared data from an empty account.
private enum WidgetConfigurationLoadError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "Widget data is unavailable. Open PadBuddy to refresh it.", table: "WidgetDataErrors")
    }
}

extension WidgetSharedStore {
    static func loadAccountsForConfiguration() throws -> [WidgetAccount] {
        let decoded: [WidgetAccount] = try configurationValue(
            fileName: accountsFile, purpose: "widget account index"
        ) ?? []
        let bounded = boundedAccounts(decoded)
        guard decoded.isEmpty || !bounded.isEmpty else { throw WidgetConfigurationLoadError.unavailable }

        return bounded
    }

    static func loadFavoritesForConfiguration(account: String) throws -> [WidgetQuestion] {
        try loadFavoritesForConfiguration(accounts: [account])[account] ?? []
    }

    static func loadFavoritesForConfiguration(accounts: [String]) throws -> [String: [WidgetQuestion]] {
        var values: [String: [WidgetQuestion]] = [:]
        for account in accounts {
            let decoded: [WidgetQuestion] = try configurationValue(
                fileName: favoritesFileName(account: account), purpose: "widget favorite questions"
            ) ?? []
            let bounded = boundedFavorites(decoded)
            guard decoded.isEmpty || !bounded.isEmpty else { throw WidgetConfigurationLoadError.unavailable }

            values[account] = bounded
        }
        return values
    }

    private static func configurationValue<Value: Decodable>(fileName: String, purpose: String) throws -> Value? {
        switch loadResult(fileName: fileName, purpose: purpose) {
        case .absent:
            return nil
        case .unreadable:
            throw WidgetConfigurationLoadError.unavailable
        case let .data(data):
            do {
                return try decoder.decode(Value.self, from: data)
            } catch {
                logger.error("Widget configuration decode failed for \(purpose, privacy: .public)")
                throw WidgetConfigurationLoadError.unavailable
            }
        }
    }
}

extension WidgetSharedStore {
    static func boundedPads(_ pads: [WidgetPadSnapshot], now: Date = .now) -> [WidgetPadSnapshot] {
        var seen = Set<String>(), bounded: [WidgetPadSnapshot] = []
        for pad in pads {
            guard bounded.count < maxReadPads else { break }
            guard let id = validatedHandoffPadID(pad.id), seen.insert(id).inserted else { continue }

            let title = presentationText(pad.title, limit: maxReadTitleCharacters)
            bounded.append(WidgetPadSnapshot(
                id: id, title: title.isEmpty ? id : title,
                subtitle: presentationText(pad.subtitle, limit: maxReadTitleCharacters),
                language: pad.language.map { presentationText($0, limit: 64) },
                updatedAt: plausibleTimestamp(pad.updatedAt, now: now)
            ))
        }
        return bounded.sorted {
            let lhs = $0.updatedAt ?? .distantPast, rhs = $1.updatedAt ?? .distantPast
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
    }

    static func boundedAccounts(_ accounts: [WidgetAccount]) -> [WidgetAccount] {
        var seen = Set<String>()
        return accounts.compactMap { account in
            guard account.id.utf8.prefix(129).count <= 128,
                  let id = validatedAccount(account.id).flatMap(\.self), seen.insert(id).inserted else { return nil }

            let name = presentationText(account.name, limit: 128)
            let legacy = account.legacyID.flatMap { validatedAccount($0).flatMap(\.self) }
            return WidgetAccount(id: id, name: name.isEmpty ? String(id.prefix(8)) : name, legacyID: legacy)
        }
    }

    static func boundedFavorites(_ questions: [WidgetQuestion]) -> [WidgetQuestion] {
        var seen = Set<Int>()
        return Array(questions.lazy.filter { $0.id > 0 && seen.insert($0.id).inserted }
            .prefix(maxReadFavorites).map { question in
                let title = presentationText(question.title, limit: maxReadTitleCharacters)
                return WidgetQuestion(id: question.id, title: title.isEmpty ? "#\(question.id)" : title)
            })
    }
}
