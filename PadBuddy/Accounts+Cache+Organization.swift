//
//  Accounts+Cache+Organization.swift
//  coderpad
//
//  The per-account organization cache, split from Accounts+Cache.swift to keep
//  that file within the lint length limit.
//

import CryptoKit
import Foundation
import os

/// Holds the last-loaded organization per account so switching to the
/// Organization section shows it instantly while a background refresh runs,
/// instead of a blocking spinner every visit. `Organization` is `Decodable`
/// only, so this is memory-only (no disk persistence like pads/questions).
@Observable
final class OrganizationCacheStore {
    static let shared = OrganizationCacheStore()
    private static let logger = Logger(subsystem: "com.coderpad.app", category: "cache")
    private var byAccount: [UUID: OrganizationCacheEntry<Organization>] = [:]

    /// Session cache + in-flight coalescing keyed by client identity (server + key),
    /// so the owner pickers, the new-pad sheet, and the org-name directory share one
    /// `/api/organization` fetch instead of each re-downloading the full teams + users
    /// payload (#374). Keyed by client rather than account because those callers hold
    /// only a `CoderPadClient`, not an account id. Memory-only, like `byAccount`.
    private var byClient: [String: Organization] = [:]
    private var statusByClient: [String: OrganizationCacheStatus] = [:]
    /// Each in-flight fetch with a per-task token, so a completing task's cleanup
    /// only removes *itself*: an unconditional clear could erase a newer task for
    /// the same identity and defeat coalescing (#1775).
    private var inFlight: [String: (token: UUID, task: Task<Organization, any Error>)] = [:]
    /// Client keys in least- to most-recently-used order; the cache holds full
    /// organization payloads and must not grow for the process lifetime as
    /// accounts re-key or endpoints multiply (#1773).
    private var clientLRU: [String] = []
    private static let clientLimit = 16

    private init() {}

    func get(_ accountID: UUID, via client: CoderPadClient) -> Organization? {
        byAccount[accountID]?.value(via: client.taskIdentity)
    }

    /// `client` is the client the organization was fetched through; a result whose
    /// credentials no longer match the account is dropped, so a load that outlived
    /// the account's removal or re-key can't resurrect its member directory (#754).
    func set(_ accountID: UUID, organization: Organization, via client: CoderPadClient) {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return }

        byAccount[accountID] = OrganizationCacheEntry(clientIdentity: client.taskIdentity, value: organization)
    }

    func remove(_ accountID: UUID) {
        byAccount[accountID] = nil
    }

    /// Drops the cache entry and cancels any in-flight fetch derived from this
    /// client identity, so a removed or re-keyed account leaves neither its API
    /// key nor its organization/member directory resident (#718, #883). The
    /// account-keyed snapshot is removed separately via ``remove(_:)``.
    func remove(baseURL: URL, apiKey: String) {
        let key = Self.clientKey(baseURL: baseURL, apiKey: apiKey)
        byClient[key] = nil
        statusByClient[key] = nil
        clientLRU.removeAll { $0 == key }
        inFlight[key]?.task.cancel()
        inFlight[key] = nil
    }

    /// Fetches the organization for `client`, coalescing concurrent callers. A fresh
    /// cache hit returns immediately; a stale one is revalidated before use and falls
    /// back to the cached copy with explicit error metadata when refresh fails (#1454).
    func organization(via client: CoderPadClient) async throws -> Organization {
        let key = Self.clientKey(client)
        if let cached = byClient[key] {
            if status(via: client)?.isStale == false {
                return cached
            }
            return try await organizationWithStaleFallback(cached: cached) {
                try await self.fetch(client, key: key)
            }
        }
        return try await fetch(client, key: key)
    }

    func status(via client: CoderPadClient, now: Date = Date()) -> OrganizationCacheStatus? {
        statusByClient[Self.clientKey(client)].map { status in
            var status = status
            status.isStale = now.timeIntervalSince(status.refreshedAt) > 5 * 60
            return status
        }
    }

    private func fetch(_ client: CoderPadClient, key: String) async throws -> Organization {
        // Coalesce: a concurrent caller for the same client awaits the same task rather
        // than starting a second identical request.
        if let existing = inFlight[key] {
            return try await cancellableValue(of: existing.task)
        }

        let token = UUID()
        let task = Task { try await client.organization() }
        inFlight[key] = (token, task)
        Task { [weak self] in
            let result = await task.result
            self?.finishFetch(result, client: client, key: key, token: token, task: task)
        }
        return try await cancellableValue(of: task)
    }

    private func finishFetch(
        _ result: Result<Organization, any Error>, client: CoderPadClient,
        key: String, token: UUID, task: Task<Organization, any Error>
    ) {
        // Only this task's own registration is cleared: an account removed and
        // re-added while it unwound may have started a newer fetch under the same
        // identity, and erasing that fetch would defeat coalescing (#1775).
        guard inFlight[key]?.token == token else { return }

        inFlight[key] = nil

        switch result {
        case let .success(org):
            // A fetch cancelled by account teardown may still complete (the request
            // isn't obliged to honour cancellation); caching its result would
            // repopulate the just-purged credentials and members (#718).
            guard !task.isCancelled else { return }

            byClient[key] = org
            statusByClient[key] = OrganizationCacheStatus(
                refreshedAt: Date(),
                isStale: false,
                refreshError: nil
            )
            touchClientKey(key)

        case let .failure(error):
            if let previous = statusByClient[key] {
                statusByClient[key] = OrganizationCacheStatus(
                    refreshedAt: previous.refreshedAt,
                    isStale: true,
                    refreshError: error.localizedDescription
                )
            }
            // The error text can carry server-provided detail; it stays private in
            // production logs while the host remains public for diagnosis (#1776).
            Self.logger.warning(
                """
                Organization fetch failed for host '\(Self.safeHost(client), privacy: .public)': \
                \(error.localizedDescription, privacy: .private)
                """
            )
        }
    }

    /// Marks a client key most-recently-used and evicts the oldest past the cap (#1773).
    private func touchClientKey(_ key: String) {
        clientLRU.removeAll { $0 == key }
        clientLRU.append(key)
        while clientLRU.count > Self.clientLimit {
            let evicted = clientLRU.removeFirst()
            byClient[evicted] = nil
            statusByClient[evicted] = nil
        }
    }

    private static func clientKey(_ client: CoderPadClient) -> String {
        clientKey(baseURL: client.baseURL, apiKey: client.apiKey)
    }

    static func clientKey(baseURL: URL, apiKey: String) -> String {
        // Length-prefixed then digested: an opaque identity that can't collide on
        // a separator character inside the URL or key (#1772) and never retains
        // the raw credential in a debuggable structure (#1774).
        // Use the same canonical endpoint spelling as account deduplication and
        // cache teardown, so cosmetic URL edits share one organization payload
        // instead of retaining duplicate member directories (#5135).
        let url = Account.serverIdentity(of: baseURL)
        let material = "\(url.utf8.count):\(url)|\(apiKey.utf8.count):\(apiKey)"
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func safeHost(_ client: CoderPadClient) -> String {
        guard let host = client.baseURL.host, !host.isEmpty else { return "unknown" }

        return host
    }
}

func organizationWithStaleFallback<Value: Sendable>(
    cached: Value, refresh: @Sendable () async throws -> Value
) async throws -> Value {
    do {
        return try await refresh()
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        return cached
    }
}

struct OrganizationCacheStatus: Equatable {
    let refreshedAt: Date
    var isStale: Bool
    let refreshError: String?
}

nonisolated struct OrganizationCacheEntry<Value> {
    let clientIdentity: ClientTaskIdentity
    let value: Value

    func value(via currentClientIdentity: ClientTaskIdentity) -> Value? {
        clientIdentity == currentClientIdentity ? value : nil
    }
}
