//
//  MCPAccountDirectory.swift
//  coderpad
//
//  The account model the in-app MCP server acts as. These plain Sendable value types were
//  extracted from the app's main-actor `Account` (the secrets are read on the main actor
//  in `MCPAccountLoader`), letting the rest of the headless server stay `nonisolated`.
//  They previously lived in the BuddyMCP package, which hand-rolled the JSON-RPC server;
//  that server is now MCPKit's `MCPServer` over the official MCP Swift SDK (see
//  `MCPServer.swift`), so the model lives here with the only code that uses it.
//

import Foundation

/// The minimal, Sendable credentials a tool needs: an API key, the resolved base URL,
/// and the account's identity (id, display name, resolved user email) for identity tools
/// like `whoami` / `list_accounts`. The id / name / email are NOT secrets; the API key is
/// the only sensitive field and tools never return it.
nonisolated struct MCPCredentials: Sendable {
    let id: String
    let apiKey: String
    let baseURL: URL
    let accountName: String
    let userEmail: String
    /// An optional secondary API key + base URL (e.g. a companion product), when the
    /// account has one. nil means the tools that need it can't act as this account. Like
    /// the primary key, never returned by a tool.
    var secondaryApiKey: String?
    var secondaryBaseURL: URL?

    init(
        id: String,
        apiKey: String,
        baseURL: URL,
        accountName: String,
        userEmail: String,
        secondaryApiKey: String? = nil,
        secondaryBaseURL: URL? = nil
    ) {
        self.id = id
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.accountName = accountName
        self.userEmail = userEmail
        self.secondaryApiKey = secondaryApiKey
        self.secondaryBaseURL = secondaryBaseURL
    }
}

/// All the accounts the server can act as, plus which one is the default. Lets the server
/// serve any configured account, not just the selected one: tools take an optional
/// `account` argument and `resolve(_:)` maps it to one account.
nonisolated struct MCPAccountDirectory: Sendable {
    let accounts: [MCPCredentials]
    /// The id of the account selected in the app, used when no `account` argument is given.
    let currentID: String?
    /// Whether write tools are advertised and permitted. Off unless the host app opts in.
    var allowWrites: Bool

    init(accounts: [MCPCredentials], currentID: String?, allowWrites: Bool = false) {
        self.accounts = accounts
        self.currentID = currentID
        self.allowWrites = allowWrites
    }

    /// Whether any configured account has a secondary key, so tool families that need one
    /// are worth advertising. A call still resolves the specific account's credentials.
    var secondaryAvailable: Bool {
        accounts.contains { $0.secondaryApiKey?.isEmpty == false }
    }

    /// The default account: the app-selected one, or the first configured if that id is
    /// missing, or nil when nothing is configured.
    var current: MCPCredentials? {
        if let currentID, let match = accounts.first(where: { $0.id == currentID }) { return match }
        return accounts.first
    }

    /// Resolves a tool's `account` argument to one account. A nil/empty selector picks the
    /// default; otherwise it matches by id (UUID string) first, then case-insensitively by
    /// display name. Returns nil when a non-empty selector matches nothing.
    func resolve(_ selector: String?) -> MCPCredentials? {
        guard let selector = selector?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selector.isEmpty
        else { return current }

        if let byID = accounts.first(where: { $0.id == selector }) { return byID }
        return accounts.first { $0.accountName.caseInsensitiveCompare(selector) == .orderedSame }
    }
}
