//
//  DesignSystem+Org.swift
//  coderpad
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI

// MARK: - EmailLink

struct EmailLink: View {
    let email: String

    var body: some View {
        if email.isEmpty {
            Text("(no email)").foregroundStyle(.secondary)
        } else if let url = Self.mailtoURL(for: email) {
            Link(email, destination: url)
        } else {
            Text(email)
        }
    }

    /// Built with URLComponents so query/fragment characters in a malformed API
    /// email value are percent-encoded into the address instead of rewriting the
    /// mailto destination or silently failing (#1697).
    static func mailtoURL(for email: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        return components.url
    }
}

// MARK: - OwnerName

/// A pad or question owner's name, rendered as inert display text. When the org
/// directory doesn't know the name, callers may provide a non-email fallback
/// label for privacy-sensitive surfaces.
struct OwnerName: View {
    let email: String
    let fallbackLabel: String?
    @Environment(\.orgDirectory) private var directory

    init(email: String, fallbackLabel: String? = nil) {
        self.email = email
        self.fallbackLabel = fallbackLabel
    }

    var body: some View {
        if email.isEmpty {
            Text("(no owner)").foregroundStyle(.secondary)
        } else {
            let name = directory.name(for: email) ?? fallbackLabel ?? email
            Text(name)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Owner \(name)")
        }
    }
}

// MARK: - Org directory (email -> name lookup)

@Observable
final class OrgDirectory {
    /// The stable default for `EnvironmentValues.orgDirectory`, so the `@Entry` value
    /// isn't reallocated on every access (the real directory is injected at the window
    /// root in `ContentView`). MainActor-isolated like the type, matching the env access.
    static let placeholder = OrgDirectory()

    private(set) var nameByEmail: [String: String] = [:]
    /// Bumped whenever `nameByEmail` is replaced, so list memo caches can key on
    /// directory *content* changes. Keying on the map's count missed a reload
    /// where members were renamed but the count stayed equal, leaving filtered
    /// results computed against the old names (#1198, #1214).
    private(set) var revision = 0
    /// The organization's default coding language, used to pre-select the picker
    /// in the New Pad / New Question sheets. `nil` until the org loads or when the
    /// org reports no default.
    private(set) var defaultLanguage: String?
    /// The client identity (account + endpoint + key) the directory was loaded
    /// through, so editing an account's credentials or server reloads instead of
    /// no-opping on a matching account id (#1690). Nil in merged mode.
    private var loadedClientKey: String?
    private var inFlight: UUID?
    /// Orders overlapping `load`/`loadMerged` calls: whichever started last wins,
    /// so a slow response for the previous view mode can't overwrite the
    /// directory the current mode just applied (#1692).
    private var loadGeneration = 0

    /// Seed the name map from disk so pad/question rows resolve owner names on the
    /// very first render after a cold launch, instead of flashing the raw email
    /// until the organization fetch returns. Mirrors the pads/questions caches'
    /// stale-while-revalidate: the persisted snapshot warms the UI, then the async
    /// `load`/`loadMerged` refreshes it from the network.
    ///
    /// `seedFromDisk` defaults to true for production. Tests that assert on a
    /// directory's load behavior pass `false` so a persisted `DirectoryCache` left on
    /// disk by a real app run (the cache dir is shared, not sandboxed per test) can't
    /// pre-populate the map and make a "fresh" directory look non-empty.
    init(seedFromDisk: Bool = true) {
        nameByEmail = seedFromDisk ? Self.cachedSeed() : [:]
    }

    /// The persisted name map for whichever list appears first: the union of every
    /// mergeable account in the combined view, or just the current account
    /// otherwise. Read synchronously so the first row render already has names.
    private static func cachedSeed() -> [String: String] {
        let store = AccountsStore.shared
        if store.isMergedView {
            var merged: [String: String] = [:]
            for account in store.mergeableAccounts {
                merged.merge(normalizedKeys(DirectoryCache.load(account: account.id))) { first, _ in first }
            }
            return merged
        }
        if let id = store.currentAccount?.id {
            return normalizedKeys(DirectoryCache.load(account: id))
        }
        return [:]
    }

    /// Normalizes a persisted (possibly legacy, raw-cased) map onto the lowercased
    /// keys lookups use (#1689).
    private static func normalizedKeys(_ map: [String: String]) -> [String: String] {
        var normalized: [String: String] = [:]
        for (email, name) in map {
            let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, normalized[key] == nil else { continue }

            normalized[key] = name
        }
        return normalized
    }

    /// A stable identity for the credentials a directory load runs through (#1690).
    private static func clientKey(for account: Account) -> String {
        "\(account.id.uuidString)|\(account.resolvedBaseURL.absoluteString)|\(account.apiKey.hashValue)"
    }

    func load(for account: Account) async {
        let clientKey = Self.clientKey(for: account)
        guard loadedClientKey != clientKey, inFlight != account.id else { return }

        inFlight = account.id
        loadGeneration += 1
        let generation = loadGeneration
        defer { inFlight = nil }
        let client = account.makeClient()
        if let org = try? await OrganizationCacheStore.shared.organization(via: client) {
            // A session change cancels the navigation loader that called this;
            // a stale load must not overwrite the new session's directory (#1239),
            // and an overlapping merged load that started later wins (#1692).
            guard !Task.isCancelled, generation == loadGeneration else { return }

            let map = Self.nameMap(of: org)
            nameByEmail = map
            revision += 1
            defaultLanguage = org.organizationDefaultLanguage.flatMap { $0.isEmpty ? nil : $0 }
            loadedClientKey = clientKey
            // Persist for the next cold launch. The fetch succeeded, so an empty
            // map is the organization's real state: writing it through is what
            // stops removed members reappearing from a stale snapshot (#1694).
            DirectoryCache.save(map, account: account.id)
        }
    }

    /// The email → display-name map of an organization's members. Emails are
    /// normalized (trimmed, lowercased) so owner records with case variations
    /// resolve the same member (#1689); names are trimmed and whitespace-only
    /// ones dropped so they can't override the email with a blank label (#1696).
    private nonisolated static func nameMap(of org: Organization) -> [String: String] {
        var map: [String: String] = [:]
        for user in org.users {
            let email = user.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !email.isEmpty, map[email] == nil,
                  let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { continue }

            map[email] = name
        }
        return map
    }

    /// Load and union the member directories of several accounts at once, for the
    /// combined "All Accounts" view where owner emails span every org. Fetches each
    /// account's organization concurrently and merges the name maps so a pad from
    /// any account can still resolve its owner's display name. `loadedClientKey` is
    /// cleared so a later single-account `load` refreshes rather than no-ops.
    func loadMerged(for accounts: [Account]) async {
        let realAccounts = accounts.filter { !$0.apiKey.isEmpty }
        guard !realAccounts.isEmpty else { return }

        loadGeneration += 1
        let generation = loadGeneration
        let mapsByID = await withTaskGroup(of: (UUID, [String: String]?).self) { group -> [UUID: [String: String]] in
            for account in realAccounts {
                let client = account.makeClient()
                let id = account.id
                group.addTask {
                    guard let org = try? await OrganizationCacheStore.shared.organization(via: client) else {
                        return (id, nil)
                    }

                    return (id, Self.nameMap(of: org))
                }
            }
            var collected: [UUID: [String: String]] = [:]
            for await (id, map) in group {
                collected[id] = map
            }
            return collected
        }
        // A session change cancels the navigation loader that called this; a stale
        // merged load must not overwrite the new session's directory (#1239), and
        // an overlapping single-account load that started later wins (#1692).
        guard !Task.isCancelled, generation == loadGeneration else { return }

        // Merge in the accounts' configured order, not the task group's completion
        // order, so an email shared by two organizations always resolves to the
        // same name across refreshes (#1691).
        var merged: [String: String] = [:]
        for account in realAccounts {
            guard let map = mapsByID[account.id] else { continue }

            merged.merge(map) { first, _ in first }
            // Persist each account's own map (not the union) so a later single-account
            // launch seeds from just that account. A fetched empty map is the org's
            // real state and overwrites the snapshot (#1694); only failed fetches
            // (nil above) leave the previous snapshot alone.
            DirectoryCache.save(map, account: account.id)
        }
        nameByEmail = merged
        revision += 1
        // The merged view spans organizations with potentially different default
        // languages; keeping the previous single account's default would seed
        // new-item flows with the wrong org's language (#1693).
        defaultLanguage = nil
        loadedClientKey = nil
    }

    func name(for email: String) -> String? {
        // Emails are stored normalized (trimmed, lowercased), so a record with
        // different casing still resolves the same member (#1689).
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        return nameByEmail[normalized]
    }

    func display(_ email: String) -> String {
        name(for: email) ?? email
    }
}

/// Disk backing for `OrgDirectory`'s email -> name map, one JSON file per account
/// under Application Support (via the shared `CacheDisk`). Lets owner names resolve
/// on the first render after a cold launch, the same stale-while-revalidate trick
/// the pads and questions lists already use. Snapshots are stamped and expire
/// after 30 days: without a refresh in that window, outdated member names must
/// not keep presenting indefinitely (#1695).
private enum DirectoryCache {
    /// The stamped snapshot format; legacy files (a bare `[String: String]`) still
    /// read, they just carry no stamp and are treated as fresh until re-saved.
    private nonisolated struct Snapshot: Codable {
        let names: [String: String]
        let savedAt: Date

        init(names: [String: String], savedAt: Date) {
            self.names = names
            self.savedAt = savedAt
        }

        /// Accepts the current envelope *or* the legacy bare `[String: String]` map.
        ///
        /// `load` used to decode the envelope, and on failure read and decode the very
        /// same file a second time as the legacy shape — two synchronous disk reads per
        /// mergeable account during cold-launch seeding, on the main actor (#2449).
        /// Handling both here means one read either way. A legacy snapshot carries no
        /// timestamp, so it is treated as fresh, exactly as the separate legacy path
        /// did by skipping the age check.
        init(from decoder: any Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self),
               let names = try? container.decode([String: String].self, forKey: .names) {
                self.names = names
                savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date()
                return
            }

            names = try decoder.singleValueContainer().decode([String: String].self)
            savedAt = Date()
        }
    }

    private nonisolated static let maxAge: TimeInterval = 30 * 24 * 60 * 60

    nonisolated static func load(account: UUID) -> [String: String] {
        guard let snapshot = CacheDisk.load(Snapshot.self, kind: "directory", account: account) else { return [:] }
        guard Date().timeIntervalSince(snapshot.savedAt) <= maxAge else { return [:] }

        return snapshot.names
    }

    nonisolated static func save(_ map: [String: String], account: UUID) {
        CacheDisk.save(Snapshot(names: map, savedAt: Date()), kind: "directory", account: account)
    }
}

extension EnvironmentValues {
    @Entry var orgDirectory = OrgDirectory.placeholder
    // `EnvironmentValues.isReadOnly` now lives in `BuddyDesignSystem` (#321), re-exported
    // via `DesignSystem.swift`, so the app's editing controls keep reading `\.isReadOnly`
    // unqualified. The `FocusedValues.isReadOnly` counterpart below is a separate key.
}

// APIErrorView lives in DesignSystem+APIErrorView.swift (split out for file length).
// Focused scene values and list copy/link helpers live in
// DesignSystem+FocusedActions.swift (split out for file length).
