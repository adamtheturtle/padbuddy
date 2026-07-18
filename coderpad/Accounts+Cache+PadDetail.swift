//
//  Accounts+Cache+PadDetail.swift
//  coderpad
//
//  The per-pad detail cache, split out of Accounts+Cache.swift for file length.
//

import Foundation

/// Holds the last-loaded events and environments per pad, so re-selecting a pad
/// the user already opened this session shows its detail instantly while a
/// background refresh runs, instead of a blocking spinner on every switch (#323).
/// Memory-only: this data is session-scoped and refreshed on every open, so —
/// like `OrganizationCacheStore` — there's no disk backing.
@Observable
final class PadDetailCacheStore {
    static let shared = PadDetailCacheStore()

    struct Key: Hashable {
        var padID: String
        var baseURL: URL
        var apiKey: String

        init(padID: String, client: CoderPadClient) {
            self.padID = padID
            baseURL = client.baseURL
            apiKey = client.apiKey
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

    private(set) var byPad: [Key: Entry] = [:]
    /// Cache keys in least- to most-recently-opened order, so an overflow evicts the
    /// least-recently-used entry. Bookkeeping only, so it stays out of observation.
    @ObservationIgnored private var lru: [Key] = []
    private init() {}

    func get(_ padID: String, client: CoderPadClient) -> Entry? {
        byPad[Key(padID: padID, client: client)]
    }

    func set(_ padID: String, client: CoderPadClient, events: [PadEvent], environments: [PadEnvironment]) {
        let key = Key(padID: padID, client: client)
        let histories = byPad[key]?.histories ?? []
        set(key, events: events, environments: environments, histories: histories)
    }

    func set(_ padID: String, client: CoderPadClient, events: [PadEvent], environments: [PadEnvironment],
             histories: [PadFileHistory]) {
        set(Key(padID: padID, client: client), events: events, environments: environments, histories: histories)
    }

    private func set(_ key: Key, events: [PadEvent], environments: [PadEnvironment], histories: [PadFileHistory]) {
        byPad[key] = Entry(events: events, environments: environments, histories: histories)
        // Mark this pad most-recently-used, then evict the oldest while over the cap.
        // `set` runs on every open (load() refreshes), so set-order tracks open-order.
        lru.removeAll { $0 == key }
        lru.append(key)
        while lru.count > Self.limit {
            byPad[lru.removeFirst()] = nil
        }
    }

    func remove(_ padID: String, client: CoderPadClient) {
        let key = Key(padID: padID, client: client)
        byPad[key] = nil
        lru.removeAll { $0 == key }
    }

    /// Drops every cached detail fetched with this client identity, so removing
    /// or re-keying an account leaves none of its candidate code, event logs, or
    /// histories resident (#884, #719).
    func remove(baseURL: URL, apiKey: String) {
        let stale = byPad.keys.filter { $0.baseURL == baseURL && $0.apiKey == apiKey }
        for key in stale {
            byPad[key] = nil
        }
        lru.removeAll(where: stale.contains)
    }
}
