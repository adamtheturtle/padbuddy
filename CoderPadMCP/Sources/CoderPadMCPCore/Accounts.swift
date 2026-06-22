//
//  Accounts.swift
//  CoderPadMCPCore
//
//  Multi-account configuration for the standalone server (#521). The CLI can act as
//  several CoderPad accounts — mirroring the in-app server's account directory — so the
//  `account` tool argument and `list_accounts` resolve the same way on both servers and
//  one shared tool schema fits each. Accounts come from a JSON config file; a single
//  account can still be supplied via the legacy environment variables, which becomes the
//  lone (default) account so existing setups keep working. Pure parsing, kept here so
//  it's unit-tested without touching the filesystem.
//

import Foundation

/// One configured CoderPad account the standalone server can act as.
public struct MCPAccount: Equatable, Sendable {
    public let name: String
    public let apiKey: String
    public let baseURL: URL
    /// CoderPad Screen (assessments) is a separate API with its own key; nil disables
    /// the screen_* tools for this account.
    public let screenAPIKey: String?
    /// "eu" for EU-hosted Screen orgs, else "us".
    public let screenRegion: String

    public init(name: String, apiKey: String, baseURL: URL, screenAPIKey: String?, screenRegion: String) {
        self.name = name
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.screenAPIKey = screenAPIKey
        self.screenRegion = screenRegion
    }

    public var screenEnabled: Bool {
        screenAPIKey != nil
    }

    /// The Screen API host for this account's region.
    public var screenBaseURL: URL {
        screenRegion == "eu"
            ? URL(string: "https://www.codingame.eu")!
            : URL(string: "https://www.codingame.com")!
    }
}

/// The full set of accounts the server resolves tool calls against, plus the global
/// write opt-in.
public struct MCPAccountSet: Equatable, Sendable {
    public let accounts: [MCPAccount]
    /// The name of the account used when a tool call omits `account`.
    public let defaultName: String
    public let allowWrites: Bool

    public init(accounts: [MCPAccount], defaultName: String, allowWrites: Bool) {
        self.accounts = accounts
        self.defaultName = defaultName
        self.allowWrites = allowWrites
    }

    /// The default account (the one named `defaultName`, else the first).
    public var defaultAccount: MCPAccount {
        accounts.first { $0.name == defaultName } ?? accounts[0]
    }

    /// Resolves a tool call's `account` argument to a configured account by name
    /// (case-insensitive). A nil/empty name resolves to the default; a non-empty name
    /// that matches nothing returns nil so the caller can report the available accounts.
    public func resolve(_ name: String?) -> MCPAccount? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultAccount
        }

        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return accounts.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
    }

    /// Whether any account has Screen configured — the screen_* tools are advertised
    /// when at least one does, matching the in-app server's gating.
    public var anyScreenEnabled: Bool {
        accounts.contains(where: \.screenEnabled)
    }

    /// The directory returned by `list_accounts`: names, base URLs, and flags, never the
    /// API keys.
    public func directory() -> [[String: Any]] {
        accounts.map { account in
            [
                "name": account.name,
                "base_url": account.baseURL.absoluteString,
                "is_default": account.name == defaultName,
                "screen_configured": account.screenEnabled
            ]
        }
    }
}

/// Why a configuration couldn't be turned into a usable account set.
public enum MCPConfigError: Error, Equatable {
    case noAccounts
    case missingAPIKey(account: String)
    case duplicateName(String)
}

private func screenRegion(from raw: String?) -> String {
    raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "eu" ? "eu" : "us"
}

private func trimmedNonEmpty(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }

    return value
}

private func parseBaseURL(_ raw: String?) -> URL {
    if let raw = trimmedNonEmpty(raw), let url = URL(string: raw) { return url }
    return URL(string: "https://app.coderpad.io")!
}

private func truthy(_ raw: String?) -> Bool {
    ["1", "true", "yes", "on"].contains(raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
}

/// Builds the account set from a parsed JSON config object, falling back to the legacy
/// single-account environment variables when no config (or an empty one) is given.
///
/// Config shape:
/// ```
/// { "accounts": [ { "name": "Acme", "api_key": "…", "base_url": "…",
///                   "screen_api_key": "…", "screen_region": "eu", "default": true } ],
///   "allow_writes": false }
/// ```
/// Env fallback: `CODERPAD_API_KEY` (required), `CODERPAD_BASE_URL`,
/// `CODERPAD_SCREEN_API_KEY`, `CODERPAD_SCREEN_REGION`, `CODERPAD_MCP_ALLOW_WRITES`.
/// `allow_writes` is OR'd with the env flag, so either can enable writes.
public func makeAccountSet(config: [String: Any]?, environment: [String: String]) throws -> MCPAccountSet {
    let envWrites = truthy(environment["CODERPAD_MCP_ALLOW_WRITES"])

    if let config, let rawAccounts = config["accounts"] as? [[String: Any]], !rawAccounts.isEmpty {
        var accounts: [MCPAccount] = []
        var defaultName: String?
        var seen = Set<String>()
        for entry in rawAccounts {
            let name = trimmedNonEmpty(entry["name"] as? String) ?? "account-\(accounts.count + 1)"
            guard let key = trimmedNonEmpty(entry["api_key"] as? String) else {
                throw MCPConfigError.missingAPIKey(account: name)
            }
            guard seen.insert(name.lowercased()).inserted else {
                throw MCPConfigError.duplicateName(name)
            }

            accounts.append(MCPAccount(
                name: name,
                apiKey: key,
                baseURL: parseBaseURL(entry["base_url"] as? String),
                screenAPIKey: trimmedNonEmpty(entry["screen_api_key"] as? String),
                screenRegion: screenRegion(from: entry["screen_region"] as? String)
            ))
            if (entry["default"] as? Bool) == true, defaultName == nil { defaultName = name }
        }

        let allowWrites = envWrites || (config["allow_writes"] as? Bool == true)
        return MCPAccountSet(accounts: accounts, defaultName: defaultName ?? accounts[0].name, allowWrites: allowWrites)
    }

    // Legacy single-account env fallback.
    guard let key = trimmedNonEmpty(environment["CODERPAD_API_KEY"]) else {
        throw MCPConfigError.noAccounts
    }

    let account = MCPAccount(
        name: trimmedNonEmpty(environment["CODERPAD_ACCOUNT_NAME"]) ?? "default",
        apiKey: key,
        baseURL: parseBaseURL(environment["CODERPAD_BASE_URL"]),
        screenAPIKey: trimmedNonEmpty(environment["CODERPAD_SCREEN_API_KEY"]),
        screenRegion: screenRegion(from: environment["CODERPAD_SCREEN_REGION"])
    )
    return MCPAccountSet(accounts: [account], defaultName: account.name, allowWrites: envWrites)
}
