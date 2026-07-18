//
//  Accounts+Cache+Organization.swift
//  coderpad
//
//  The per-account organization cache, split from Accounts+Cache.swift to keep
//  that file within the lint length limit.
//

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
    private(set) var byAccount: [UUID: Organization] = [:]

    /// Session cache + in-flight coalescing keyed by client identity (server + key),
    /// so the owner pickers, the new-pad sheet, and the org-name directory share one
    /// `/api/organization` fetch instead of each re-downloading the full teams + users
    /// payload (#374). Keyed by client rather than account because those callers hold
    /// only a `CoderPadClient`, not an account id. Memory-only, like `byAccount`.
    private var byClient: [String: Organization] = [:]
    private var inFlight: [String: Task<Organization, any Error>] = [:]

    private init() {}

    func get(_ accountID: UUID) -> Organization? {
        byAccount[accountID]
    }

    /// `client` is the client the organization was fetched through; a result whose
    /// credentials no longer match the account is dropped, so a load that outlived
    /// the account's removal or re-key can't resurrect its member directory (#754).
    func set(_ accountID: UUID, organization: Organization, via client: CoderPadClient) {
        guard AccountsStore.shared.isCurrentClient(client, for: accountID) else { return }

        byAccount[accountID] = organization
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
        inFlight[key]?.cancel()
        inFlight[key] = nil
    }

    /// Fetch the organization for `client`, coalescing concurrent callers onto one
    /// request and serving a cached copy when one exists — stale-while-revalidate: a
    /// cached hit returns immediately and kicks off a background refresh. Only throws
    /// when there's no cached copy and the fetch fails (#374).
    func organization(via client: CoderPadClient) async throws -> Organization {
        let key = Self.clientKey(client)
        if let cached = byClient[key] {
            refreshInBackground(client, key: key)
            return cached
        }
        return try await fetch(client, key: key)
    }

    private func fetch(_ client: CoderPadClient, key: String) async throws -> Organization {
        // Coalesce: a concurrent caller for the same client awaits the same task rather
        // than starting a second identical request.
        if let existing = inFlight[key] { return try await existing.value }

        let task = Task { try await client.organization() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        do {
            let org = try await task.value
            // A fetch cancelled by account teardown may still complete (the request
            // isn't obliged to honour cancellation); caching its result would
            // repopulate the just-purged credentials and members (#718).
            if !task.isCancelled {
                byClient[key] = org
            }
            return org
        } catch {
            Self.logger.warning(
                """
                Organization fetch failed for host '\(Self.safeHost(client), privacy: .public)': \
                \(error.localizedDescription, privacy: .public)
                """
            )
            throw error
        }
    }

    private func refreshInBackground(_ client: CoderPadClient, key: String) {
        guard inFlight[key] == nil else { return }

        Task {
            do {
                _ = try await fetch(client, key: key)
            } catch {
                // `fetch` logs the privacy-safe failure context; keep the stale copy.
            }
        }
    }

    private static func clientKey(_ client: CoderPadClient) -> String {
        clientKey(baseURL: client.baseURL, apiKey: client.apiKey)
    }

    private static func clientKey(baseURL: URL, apiKey: String) -> String {
        "\(baseURL.absoluteString)|\(apiKey)"
    }

    private static func safeHost(_ client: CoderPadClient) -> String {
        guard let host = client.baseURL.host, !host.isEmpty else { return "unknown" }

        return host
    }
}
