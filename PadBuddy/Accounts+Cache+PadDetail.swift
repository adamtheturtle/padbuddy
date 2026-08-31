//
//  Accounts+Cache+PadDetail.swift
//  coderpad
//
//  The per-pad detail cache, split out of Accounts+Cache.swift for file length.
//

import CryptoKit
import Foundation

/// Holds the last-loaded events and environments per pad, so re-selecting a pad
/// the user already opened this session shows its detail instantly while a
/// background refresh runs, instead of a blocking spinner on every switch (#323).
/// Memory-only: this data is session-scoped and refreshed on every open, so —
/// like `OrganizationCacheStore` — there's no disk backing.
@Observable
final class PadDetailCacheStore {
    static let shared = PadDetailCacheStore()

    /// A client identity as the cache tracks it: the server plus a digest of the
    /// API key. The digest, never the key itself — cache keys sit in an
    /// observable dictionary for the whole session and must not keep raw
    /// credentials resident for memory inspection (#1767).
    struct ClientIdentity: Hashable {
        var baseURL: URL
        var apiKeyDigest: String

        init(baseURL: URL, apiKey: String) {
            self.baseURL = Self.normalized(baseURL)
            apiKeyDigest = SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        /// Canonicalizes an endpoint so equivalent spellings compare equal.
        ///
        /// Identities were compared by exact `URL` equality, so the same server
        /// written with a trailing slash, a different host casing, or an explicit
        /// default port produced a different identity. Removing an account then
        /// missed entries cached under the other spelling and left that pad's
        /// candidate code and event log resident (#2616). Mirrors the normalization
        /// `Account.syncID` already does for the same reason.
        private static func normalized(_ url: URL) -> URL {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }

            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            // The explicit default port is dropped, which this normalization named as
            // one of the spellings it collapses but never handled: `https://host:443`
            // and `https://host` stayed distinct identities, so `ClientCacheTeardown`
            // retired one while a pad's events, environments, and replayed histories
            // stayed resident under the other (#4804). Both `Account.serverIdentity`
            // and `Account.syncEndpointID` already drop it.
            let scheme = components.scheme
            if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
                components.port = nil
            }
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = path.isEmpty ? "" : "/\(path)"
            components.query = nil
            components.fragment = nil
            return components.url ?? url
        }
    }

    struct Key: Hashable {
        var padID: String
        var identity: ClientIdentity

        init(padID: String, client: CoderPadClient) {
            self.padID = padID
            identity = ClientIdentity(baseURL: client.baseURL, apiKey: client.apiKey)
        }

        init(padID: String, identity: ClientIdentity) {
            self.padID = padID
            self.identity = identity
        }
    }

    struct Entry {
        var events: [PadEvent]
        var environments: [PadEnvironment]
        var histories: [PadFileHistory]
    }

    /// How many pads' detail payloads stay resident at once. Each entry holds a pad's
    /// full event log and all of its environments (which carry code-file contents), so
    /// an uncapped map grew without bound for the whole session — hundreds of KB per
    /// long pad (#421, a cause of #418). Keeping the most-recently-opened handful
    /// preserves the instant re-open behaviour (#323) while bounding memory, mirroring
    /// the count caps the other in-process caches already use.
    private static let limit = 12
    /// The largest single entry worth keeping resident (#1768): one pathological pad
    /// (an enormous history or file set) must not defeat the count cap. Oversized
    /// loads still display; they just aren't cached for re-open.
    private static let maxEntryBytes = 8_000_000

    private(set) var byPad: [Key: Entry] = [:]
    /// Cache keys in least- to most-recently-opened order, so an overflow evicts the
    /// least-recently-used entry. Bookkeeping only, so it stays out of observation.
    @ObservationIgnored private var lru: [Key] = []
    /// Client identities torn down by account removal/re-key. A detail request begun
    /// under old credentials can complete after the purge; its late `set` must not
    /// reinsert candidate data under the retired key (#1765). An identity that
    /// becomes live again (the account re-added) is reinstated by
    /// `ClientCacheTeardown.reconcile`.
    @ObservationIgnored private var retired: Set<ClientIdentity> = []
    private init() {}

    func get(_ padID: String, client: CoderPadClient) -> Entry? {
        let key = Key(padID: padID, client: client)
        guard let entry = byPad[key] else { return nil }

        // A read is a use: a frequently reopened pad whose refresh keeps failing
        // must not be evicted as if it were never accessed (#1766).
        lru.removeAll { $0 == key }
        lru.append(key)
        return entry
    }

    /// Caches a load that has no histories yet.
    ///
    /// Histories are deliberately *not* carried over from the previous entry. This
    /// overload is called partway through a refresh — fresh events and environments
    /// are in hand, the histories are still loading — and keeping the old ones
    /// pinned them alongside the new files. A user who left and returned in that
    /// window saw a previous state's code history presented against current files
    /// (#2626), and a refresh that legitimately found no histories left the old ones
    /// on screen (#2627). Showing none briefly, until the follow-up `set` supplies
    /// the real ones, is the honest version.
    func set(_ padID: String, client: CoderPadClient, events: [PadEvent], environments: [PadEnvironment]) {
        set(Key(padID: padID, client: client), events: events, environments: environments, histories: [])
    }

    func set(_ padID: String, client: CoderPadClient, events: [PadEvent], environments: [PadEnvironment],
             histories: [PadFileHistory]) {
        set(Key(padID: padID, client: client), events: events, environments: environments, histories: histories)
    }

    private func set(_ key: Key, events: [PadEvent], environments: [PadEnvironment], histories: [PadFileHistory]) {
        // A late load that outlived its account's removal or re-key must not
        // repopulate the cache under the retired identity (#1765).
        guard !retired.contains(key.identity) else { return }

        let entry = Entry(events: events, environments: environments, histories: histories)
        guard Self.approximateBytes(of: entry) <= Self.maxEntryBytes else {
            // Over the byte cap (#1768): drop any stale cached copy too, so a
            // re-open can't serve an older, smaller snapshot as current.
            byPad[key] = nil
            lru.removeAll { $0 == key }
            return
        }

        byPad[key] = entry
        // Mark this pad most-recently-used, then evict the oldest while over the cap.
        // `set` runs on every open (load() refreshes), so set-order tracks open-order.
        lru.removeAll { $0 == key }
        lru.append(key)
        while lru.count > Self.limit {
            byPad[lru.removeFirst()] = nil
        }
    }

    /// A rough resident-size estimate: file and snapshot contents dominate a pad
    /// detail entry, but its events are measured rather than assumed (#1768).
    ///
    /// Events used to be charged a flat 200 bytes each. A `PadEvent` is not a
    /// fixed-size record — its `message` is server-provided and can be arbitrarily
    /// long, which is why `PadEventGrouping.identitySuffix(for:)` treats the derived
    /// identity as unbounded — so a pad with a heavy event log was admitted far past
    /// `maxEntryBytes` and pinned for the session, which is the case the cap exists
    /// for (#4806).
    private static func approximateBytes(of entry: Entry) -> Int {
        var total = 0
        for event in entry.events {
            // The fixed part covers the struct itself and the short fields; the
            // variable strings are measured.
            total += 200
            total += event.message.utf8.count
            total += event.metadata?.utf8.count ?? 0
            total += event.userName?.utf8.count ?? 0
            total += event.userEmail?.utf8.count ?? 0
        }
        for environment in entry.environments {
            for file in environment.fileContents {
                total += file.contents?.utf8.count ?? 0
            }
        }
        for history in entry.histories {
            total += history.retainedSnapshotContentBytes
        }
        return total
    }

    func remove(_ padID: String, client: CoderPadClient) {
        let key = Key(padID: padID, client: client)
        byPad[key] = nil
        lru.removeAll { $0 == key }
    }

    /// Removes one pad fetched by an identity whose account record may already be
    /// gone. The deletion broadcast retains the original credentials, so a
    /// same-slug entry belonging to another server must remain cached (#5148).
    func remove(_ padID: String, clientIdentity: ClientTaskIdentity) {
        let identity = ClientIdentity(baseURL: clientIdentity.baseURL, apiKey: clientIdentity.apiKey)
        let key = Key(padID: padID, identity: identity)
        byPad[key] = nil
        lru.removeAll { $0 == key }
    }

    /// Drops every cached detail fetched with this client identity, so removing
    /// or re-keying an account leaves none of its candidate code, event logs, or
    /// histories resident (#884, #719), and retires the identity so an in-flight
    /// load can't repopulate it (#1765).
    func remove(baseURL: URL, apiKey: String) {
        let identity = ClientIdentity(baseURL: baseURL, apiKey: apiKey)
        retired.insert(identity)
        let stale = byPad.keys.filter { $0.identity == identity }
        for key in stale {
            byPad[key] = nil
        }
        lru.removeAll(where: stale.contains)
    }

    /// Marks a live client identity cacheable again: an account re-added with the
    /// same credentials must not stay blocked by its earlier retirement (#1765).
    func reinstate(baseURL: URL, apiKey: String) {
        retired.remove(ClientIdentity(baseURL: baseURL, apiKey: apiKey))
    }
}
