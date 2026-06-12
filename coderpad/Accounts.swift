//
//  Secrets.swift
//  coderpad
//
//  Multi-account key storage backed by the macOS Keychain.
//

import Foundation
import Security
import SwiftUI
import os
import os.log

nonisolated let persistenceLogger = Logger(subsystem: "com.coderpad.app", category: "persistence")

/// Serializes detached persistence writes in submission order. Without this, two
/// `Task.detached` writes issued in quick succession can finish out of order and
/// leave a stale snapshot (or an orphaned file) on disk. Each enqueued unit awaits
/// the previous one, so writes apply in the order they were submitted regardless of
/// the caller's isolation.
final class SerialWriteQueue: Sendable {
    private let tail = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    func enqueue(priority: TaskPriority = .utility, _ work: @Sendable @escaping () -> Void) {
        tail.withLock { current in
            let previous = current
            current = Task.detached(priority: priority) {
                await previous?.value
                work()
            }
        }
    }
}

struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var apiKey: String
    var isMock: Bool
    /// The email of the org member this key belongs to, used to show "my" pads.
    /// The CoderPad API doesn't expose the key's owner, so the user picks it when
    /// validating the key. Optional so accounts saved before this existed still decode.
    var userEmail: String?
    /// An optional override for the CoderPad server URL, for self-hosted or regional
    /// deployments. `nil`/empty means the standard hosted endpoint. Optional so
    /// accounts saved before this existed still decode.
    var baseURL: String?

    init(id: UUID = UUID(), name: String, apiKey: String, isMock: Bool = false, userEmail: String? = nil, baseURL: String? = nil) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.isMock = isMock
        self.userEmail = userEmail
        self.baseURL = baseURL
    }

    /// The server URL to talk to: the account's override when set and parseable,
    /// otherwise the standard hosted endpoint.
    var resolvedBaseURL: URL {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let host = url.host, !host.isEmpty {
            return url
        }
        return CoderPadClient.defaultBaseURL
    }

    /// Email of the mock data's "Demo User", who owns several of the mock pads and
    /// questions — so the demo account's "My Pads"/"My Questions" defaults return
    /// real results, and the account satisfies the required-email rule.
    static let demoUserEmail = "demo@example.com"

    static func demo() -> Account {
        Account(name: "Demo (mock data)", apiKey: "demo", isMock: true, userEmail: demoUserEmail)
    }

    /// Sentinel key marking the "bad key" demo: a mock account whose in-process
    /// server answers 401 for every request, so the unauthorized banner and error
    /// states can be demoed without a real revoked key.
    static let badKeyMockKey = "demo-bad-key"

    static func demoBadKey() -> Account {
        Account(name: "Demo (bad key)", apiKey: badKeyMockKey, isMock: true, userEmail: demoUserEmail)
    }

    /// Whether this is the bad-key demo, as opposed to the mock-data demo.
    var isBadKeyDemo: Bool { isMock && apiKey == Self.badKeyMockKey }

    /// The API client this account talks to: the in-process mock for demo accounts
    /// (answering 401 for the bad-key demo), otherwise the live hosted client.
    func makeClient() -> CoderPadClient {
        guard isMock else {
            return .live(apiKey: apiKey, baseURL: resolvedBaseURL)
        }
        return .mock(unauthorized: isBadKeyDemo)
    }

    /// A draft account pre-filled from the `CODERPAD_API_KEY` (and optional
    /// `CODERPAD_USER_EMAIL`) env vars set in the scheme's Run action, or `nil`
    /// when no key is present. Debug-only convenience so testing against real
    /// data via the Add Account button doesn't mean re-pasting the key each run;
    /// option-click the button to fill from this. Env vars are readable under the
    /// App Sandbox, unlike a home-directory dotfile — keep that scheme non-shared
    /// (xcuserdata) so the key never lands in git.
    static func fromDevEnvironment() -> Account? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let rawKey = env["CODERPAD_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawKey.isEmpty else { return nil }
        let trimmedEmail = env["CODERPAD_USER_EMAIL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let email = (trimmedEmail?.isEmpty == false) ? trimmedEmail : nil
        return Account(name: "Dev (env key)", apiKey: rawKey, userEmail: email)
        #else
        return nil
        #endif
    }
}

nonisolated enum Keychain {
    static let service = "com.coderpad.app"
    static let accountsAccount = "accounts"
    static let legacySingleKeyAccount = "apiKey"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Use the modern data-protection keychain so macOS doesn't prompt
            // for password on every Debug rebuild (the legacy file keychain
            // ties ACLs to the app's code signature, which changes per build).
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func readData(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return data
    }

    static func write(_ data: Data, account: String) {
        let query = baseQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                persistenceLogger.error("Keychain SecItemAdd failed for account '\(account, privacy: .public)' (OSStatus \(addStatus))")
            }
        } else if status != errSecSuccess {
            persistenceLogger.error("Keychain SecItemUpdate failed for account '\(account, privacy: .public)' (OSStatus \(status))")
        }
    }

    static func delete(account: String) {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
    }
}

@Observable
final class AccountsStore {
    static let shared = AccountsStore()

    var accounts: [Account] {
        didSet { persistAccounts() }
    }

    var currentAccountID: UUID? {
        didSet { persistCurrentID() }
    }

    var currentAccount: Account? {
        guard let id = currentAccountID else { return accounts.first }
        return accounts.first(where: { $0.id == id }) ?? accounts.first
    }

    private static let currentIDDefaultsKey = "currentAccountID"

    private init() {
        let loaded: [Account] = Self.loadAccounts() ?? []
        accounts = loaded
        if let s = UserDefaults.standard.string(forKey: Self.currentIDDefaultsKey),
           let uuid = UUID(uuidString: s),
           loaded.contains(where: { $0.id == uuid }) {
            currentAccountID = uuid
        } else {
            currentAccountID = loaded.first?.id
        }

        if loaded.isEmpty {
            migrateLegacyIfNeeded()
        }

    }

    func add(_ account: Account) {
        accounts.append(account)
        if currentAccountID == nil { currentAccountID = account.id }
    }

    func addDemoIfMissing() {
        if !accounts.contains(where: { $0.isMock && !$0.isBadKeyDemo }) {
            add(.demo())
        }
        if let demo = accounts.first(where: { $0.isMock && !$0.isBadKeyDemo }) {
            currentAccountID = demo.id
        }
    }

    func addDemoBadKeyIfMissing() {
        if !accounts.contains(where: { $0.isBadKeyDemo }) {
            add(.demoBadKey())
        }
        if let demo = accounts.first(where: { $0.isBadKeyDemo }) {
            currentAccountID = demo.id
        }
    }

    func update(_ account: Account) {
        if let i = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[i] = account
        }
    }

    func remove(id: UUID) {
        accounts.removeAll { $0.id == id }
        if currentAccountID == id {
            currentAccountID = accounts.first?.id
        }
        // Drop the account's cached pads/questions so a removed key leaves nothing
        // behind on disk and a re-added account starts clean.
        PadsCacheStore.shared.remove(id)
        QuestionsCacheStore.shared.remove(id)
        OrganizationCacheStore.shared.remove(id)
        QuotaCacheStore.shared.remove(id)
    }

    private func migrateLegacyIfNeeded() {
        if let data = Keychain.readData(account: Keychain.legacySingleKeyAccount),
           let key = String(data: data, encoding: .utf8),
           !key.isEmpty {
            let account = Account(name: "Default", apiKey: key)
            accounts = [account]
            currentAccountID = account.id
            Keychain.delete(account: Keychain.legacySingleKeyAccount)
            return
        }
        if let legacy = UserDefaults.standard.string(forKey: "coderPadAPIKey"), !legacy.isEmpty {
            let account = Account(name: "Default", apiKey: legacy)
            accounts = [account]
            currentAccountID = account.id
            UserDefaults.standard.removeObject(forKey: "coderPadAPIKey")
        }
    }

    private static func loadAccounts() -> [Account]? {
        guard let data = Keychain.readData(account: Keychain.accountsAccount) else { return nil }
        do {
            return try JSONDecoder().decode([Account].self, from: data)
        } catch {
            persistenceLogger.error("Failed to decode accounts from Keychain — saved keys may be unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private let writeQueue = SerialWriteQueue()

    private func persistAccounts() {
        let snapshot = accounts
        // Move Keychain I/O off the main thread to keep the UI responsive, but keep
        // writes ordered so a slower earlier write can't overwrite a newer snapshot.
        writeQueue.enqueue(priority: .userInitiated) {
            if snapshot.isEmpty {
                Keychain.delete(account: Keychain.accountsAccount)
                return
            }
            do {
                let data = try JSONEncoder().encode(snapshot)
                Keychain.write(data, account: Keychain.accountsAccount)
            } catch {
                persistenceLogger.error("Failed to encode accounts snapshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func persistCurrentID() {
        if let id = currentAccountID {
            UserDefaults.standard.set(id.uuidString, forKey: Self.currentIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.currentIDDefaultsKey)
        }
    }
}

@Observable
final class AccountHealthMonitor {
    static let shared = AccountHealthMonitor()

    private(set) var unauthorizedAccountIDs: Set<UUID> = []
    private(set) var lastChecked: Date?
    private var checkTask: Task<Void, Never>?

    private init() {}

    /// Re-checks the current account's key on a fixed interval (default 30 min) so a key
    /// revoked mid-session surfaces the unauthorized banner without needing a section switch.
    /// Idempotent: repeated calls keep the single existing timer.
    func start(every interval: Duration = .seconds(1800)) {
        guard checkTask == nil else { return }
        checkTask = Task { [weak self] in
            // Validate immediately so a key already revoked before launch surfaces the
            // banner now, rather than after a full interval, then re-check on the timer.
            await self?.checkCurrentAccount()
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.checkCurrentAccount()
            }
        }
    }

    func stop() {
        checkTask?.cancel()
        checkTask = nil
    }

    func checkCurrentAccount() async {
        // The bad-key demo is intentionally checked so it surfaces the unauthorized
        // banner; the mock-data demo is skipped since it's always authorized.
        guard let account = AccountsStore.shared.currentAccount,
              account.isBadKeyDemo || (!account.isMock && !account.apiKey.isEmpty) else { return }
        let client = account.makeClient()
        do {
            _ = try await client.organization()
            unauthorizedAccountIDs.remove(account.id)
        } catch let error as CoderPadError where error.isUnauthorized {
            unauthorizedAccountIDs.insert(account.id)
        } catch {
            // transient errors don't change auth state
        }
        lastChecked = Date()
    }

    func isUnauthorized(_ accountID: UUID) -> Bool {
        unauthorizedAccountIDs.contains(accountID)
    }
}

@Observable
final class PadActivityMonitor {
    static let shared = PadActivityMonitor()
    var unseenChangedCount: Int = 0

    private init() {}

    func record(changedCount: Int) {
        if changedCount > 0 { unseenChangedCount = changedCount }
    }

    func markSeen() {
        unseenChangedCount = 0
    }
}

/// A saved filter+search snapshot. The fields are a superset across the pad and
/// question lists — pads use state/team/dateRange, questions use draft — so one
/// shape serves both. Unused fields stay `nil` for a given kind, and all are
/// optional so snapshots saved before a field existed still decode.
struct NamedSearch: Identifiable, Codable, Hashable {
    /// The longest a saved-search name may be. Names are short recall labels shown
    /// as chips, so capping them keeps any one chip from dominating the bar and
    /// guards against an accidental paste of a huge string. Enforced as the user
    /// types and again on save; chips also clamp display so names persisted before
    /// the cap existed stay bounded.
    static let maxNameLength = 40

    let id: UUID
    var name: String
    var search: String
    var stateFilter: PadState?
    var languageFilter: String?
    var ownerFilter: String?
    var teamFilter: String?
    var typeFilter: String?
    var dateRangeFilter: String?
    var draftFilter: String?

    init(id: UUID = UUID(), name: String,
         search: String = "",
         stateFilter: PadState? = nil, languageFilter: String? = nil,
         ownerFilter: String? = nil, teamFilter: String? = nil,
         typeFilter: String? = nil, dateRangeFilter: String? = nil,
         draftFilter: String? = nil) {
        self.id = id
        self.name = name
        self.search = search
        self.stateFilter = stateFilter
        self.languageFilter = languageFilter
        self.ownerFilter = ownerFilter
        self.teamFilter = teamFilter
        self.typeFilter = typeFilter
        self.dateRangeFilter = dateRangeFilter
        self.draftFilter = draftFilter
    }

    /// A plain-language list of the active filters, suitable for feeding to the
    /// on-device namer. The name itself is intentionally left out — that's what
    /// we're generating. Empty when nothing but a name is set, so callers can skip
    /// naming a search that has no distinguishing criteria to summarize.
    var filterDescription: String {
        var parts: [String] = []
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { parts.append("text contains \"\(query)\"") }
        if let stateFilter { parts.append("state is \(stateFilter.rawValue)") }
        if let languageFilter { parts.append("language is \(languageFilter)") }
        if let ownerFilter { parts.append("owner is \(ownerFilter)") }
        if let teamFilter { parts.append("team is \(teamFilter)") }
        if let typeFilter { parts.append("type is \(typeFilter)") }
        if let dateRangeFilter { parts.append("date range is \(dateRangeFilter)") }
        if let draftFilter { parts.append("draft status is \(draftFilter)") }
        return parts.joined(separator: ", ")
    }
}

/// Which list a saved search belongs to. Pads and questions have distinct filter
/// sets, so their saved searches are kept in separate buckets even though they
/// share the `NamedSearch` shape.
enum SavedSearchKind: String, Codable, Hashable {
    case pads
    case questions
}

/// Per-account saved searches for the pad and question lists. Searches are scoped
/// to the account that created them — owners, teams, and languages are all
/// account-specific, so a search saved against one org is meaningless in another —
/// and further partitioned by list kind. Persisted to UserDefaults as a single
/// JSON blob keyed by account id then kind; the encoder/decoder pair is symmetric,
/// so the nested dictionaries round-trip faithfully.
@Observable
final class SavedSearchStore {
    static let shared = SavedSearchStore()
    private var byAccount: [UUID: [String: [NamedSearch]]] = [:]
    /// True while a legacy `v1` blob is still on disk waiting to be folded in. The
    /// migration needs a current account, which may not exist yet at init, so we
    /// retry on each mutation until it succeeds.
    private var legacyPending = false
    private static let key = "savedSearches.v2"
    private static let legacyKey = "savedPadSearches.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [String: [NamedSearch]]].self, from: data) {
            byAccount = decoded
        }
        legacyPending = UserDefaults.standard.data(forKey: Self.legacyKey) != nil
        migrateLegacyIfNeeded()
    }

    func searches(account: UUID?, kind: SavedSearchKind) -> [NamedSearch] {
        guard let account else { return [] }
        return byAccount[account]?[kind.rawValue] ?? []
    }

    func add(_ search: NamedSearch, account: UUID, kind: SavedSearchKind) {
        migrateLegacyIfNeeded()
        byAccount[account, default: [:]][kind.rawValue, default: []].append(search)
        save()
    }

    func remove(id: UUID, account: UUID, kind: SavedSearchKind) {
        migrateLegacyIfNeeded()
        byAccount[account]?[kind.rawValue]?.removeAll { $0.id == id }
        save()
    }

    /// Carries pre-existing global pad searches (saved before searches became
    /// per-account) into the current account's pad bucket, so upgrading doesn't
    /// silently drop them. Folds the legacy searches in alongside any existing
    /// `v2` pad bucket rather than overwriting it, and leaves the legacy blob in
    /// place to retry later if no account is current yet.
    private func migrateLegacyIfNeeded() {
        guard legacyPending else { return }
        guard let data = UserDefaults.standard.data(forKey: Self.legacyKey),
              let legacy = try? JSONDecoder().decode([NamedSearch].self, from: data) else {
            legacyPending = false
            return
        }
        // No account to attribute the searches to yet — keep the blob and retry on
        // the next mutation (or next launch) once an account exists.
        guard let account = AccountsStore.shared.currentAccountID else { return }
        if !legacy.isEmpty {
            byAccount[account, default: [:]][SavedSearchKind.pads.rawValue, default: []]
                .insert(contentsOf: legacy, at: 0)
        }
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        legacyPending = false
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            persistenceLogger.error("Failed to encode saved searches: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Per-account favorite ("starred") questions, identified by question id. A
/// favorite is a quick-access marker: starred questions float to the top of the
/// Questions list and lead the menu bar's "New Pad from Question" submenu, so a
/// frequently used question is one click away from a fresh pad. Scoped per
/// account — a question id only means something within the org that owns it — and
/// persisted to UserDefaults as a single JSON blob keyed by account id. The
/// stored array keeps insertion order so the menu bar can lead with the questions
/// the user starred first.
@Observable
final class FavoriteQuestionsStore {
    static let shared = FavoriteQuestionsStore()
    private var byAccount: [UUID: [Int]] = [:]
    private static let key = "favoriteQuestions.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: [Int]].self, from: data) {
            byAccount = decoded
        }
    }

    func favorites(account: UUID?) -> [Int] {
        guard let account else { return [] }
        return byAccount[account] ?? []
    }

    func isFavorite(_ id: Int, account: UUID?) -> Bool {
        guard let account else { return false }
        return byAccount[account]?.contains(id) ?? false
    }

    /// Adds the question to favorites if absent, removes it if present. New
    /// favorites append to the end so the existing order is preserved.
    func toggle(_ id: Int, account: UUID) {
        var ids = byAccount[account] ?? []
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.append(id)
        }
        byAccount[account] = ids
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(byAccount)
            UserDefaults.standard.set(data, forKey: Self.key)
        } catch {
            persistenceLogger.error("Failed to encode favorite questions: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// On-disk backing for the per-account list caches. Lets pads and questions a
/// returning user already loaded appear instantly on the next cold launch, with
/// the network fetch refreshing them in the background (stale-while-revalidate).
///
/// Snapshots live in Application Support, one JSON file per account+kind. The
/// encoder/decoder pair is symmetric (default strategies), so it round-trips the
/// API models faithfully without depending on the API's date format.
enum CacheDisk {
    // nonisolated so reads/writes genuinely run off the main actor when invoked
    // from a detached task, rather than hopping back to the main thread.
    private nonisolated static let logger = Logger(subsystem: "com.coderpad.app", category: "cache")

    private nonisolated static func url(kind: String, account: UUID) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appending(path: "com.coderpad.app/DataCache", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "\(kind)-\(account.uuidString).json")
    }

    nonisolated static func load<T: Decodable>(_ type: T.Type, kind: String, account: UUID) -> T? {
        guard let url = url(kind: kind, account: account),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode \(kind, privacy: .public) cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    nonisolated static func save<T: Encodable>(_ value: T, kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to write \(kind, privacy: .public) cache: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated static func delete(kind: String, account: UUID) {
        guard let url = url(kind: kind, account: account) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

@Observable
final class PadsCacheStore {
    static let shared = PadsCacheStore()
    private(set) var padsByAccount: [UUID: [Pad]] = [:]
    /// Accounts whose disk snapshot we've already consulted, so a genuinely empty
    /// cache isn't re-read from disk on every `get`.
    private var diskConsulted: Set<UUID> = []
    private let writeQueue = SerialWriteQueue()
    private init() {}

    func get(_ accountID: UUID) -> [Pad] {
        if let cached = padsByAccount[accountID] { return cached }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Pad].self, kind: "pads", account: accountID) {
                padsByAccount[accountID] = disk
                return disk
            }
        }
        return []
    }

    /// `persist: false` updates only the in-memory snapshot, skipping the disk write —
    /// used when streaming pages so intermediate snapshots warm the UI without churning
    /// the disk; the caller persists once with the final, complete list.
    func set(_ accountID: UUID, pads: [Pad], persist: Bool = true) {
        padsByAccount[accountID] = pads
        diskConsulted.insert(accountID)
        guard persist else { return }
        writeQueue.enqueue {
            CacheDisk.save(pads, kind: "pads", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        padsByAccount[accountID] = nil
        diskConsulted.remove(accountID)
        writeQueue.enqueue {
            CacheDisk.delete(kind: "pads", account: accountID)
        }
    }
}

@Observable
final class QuestionsCacheStore {
    static let shared = QuestionsCacheStore()
    private(set) var questionsByAccount: [UUID: [Question]] = [:]
    private var diskConsulted: Set<UUID> = []
    private let writeQueue = SerialWriteQueue()
    private init() {}

    func get(_ accountID: UUID) -> [Question] {
        if let cached = questionsByAccount[accountID] { return cached }
        if !diskConsulted.contains(accountID) {
            diskConsulted.insert(accountID)
            if let disk = CacheDisk.load([Question].self, kind: "questions", account: accountID) {
                questionsByAccount[accountID] = disk
                return disk
            }
        }
        return []
    }

    func set(_ accountID: UUID, questions: [Question]) {
        questionsByAccount[accountID] = questions
        diskConsulted.insert(accountID)
        writeQueue.enqueue {
            CacheDisk.save(questions, kind: "questions", account: accountID)
        }
    }

    func remove(_ accountID: UUID) {
        questionsByAccount[accountID] = nil
        diskConsulted.remove(accountID)
        writeQueue.enqueue {
            CacheDisk.delete(kind: "questions", account: accountID)
        }
    }
}

/// Holds the last-loaded organization per account so switching to the
/// Organization section shows it instantly while a background refresh runs,
/// instead of a blocking spinner every visit. `Organization` is `Decodable`
/// only, so this is memory-only (no disk persistence like pads/questions).
@Observable
final class OrganizationCacheStore {
    static let shared = OrganizationCacheStore()
    private(set) var byAccount: [UUID: Organization] = [:]
    private init() {}

    func get(_ accountID: UUID) -> Organization? { byAccount[accountID] }
    func set(_ accountID: UUID, organization: Organization) { byAccount[accountID] = organization }
    func remove(_ accountID: UUID) { byAccount[accountID] = nil }
}

/// Holds the last-loaded quota per account, for the same reason as
/// `OrganizationCacheStore`. Shared by both the Quota and Organization sections,
/// so visiting either one warms the other.
@Observable
final class QuotaCacheStore {
    static let shared = QuotaCacheStore()
    private(set) var byAccount: [UUID: Quota] = [:]
    private init() {}

    func get(_ accountID: UUID) -> Quota? { byAccount[accountID] }
    func set(_ accountID: UUID, quota: Quota) { byAccount[accountID] = quota }
    func remove(_ accountID: UUID) { byAccount[accountID] = nil }
}

