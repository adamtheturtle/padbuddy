//
//  MCPTools.swift
//  coderpad
//
//  The read-only tool set exposed by the in-app MCP server (#402), mirroring the
//  standalone server from #393: each tool maps to one authenticated CoderPad GET and
//  returns the API's JSON verbatim, which keeps the server resilient to schema
//  additions and gives the assistant the richest representation.
//

import Foundation

nonisolated enum MCPTools {
    /// The result of running a tool: the text handed back to the assistant, and whether
    /// it should be flagged as an error (e.g. an HTTP failure).
    struct Outcome {
        let text: String
        let isError: Bool
    }

    /// Tool descriptors for `tools/list`, as plain JSON objects. Computed (not stored) so
    /// it needs no concurrency-safe shared state - a fresh array is built per call.
    static var all: [[String: Any]] {
        [
            tool("list_accounts",
                 "List the CoderPad accounts this server can act as (name, id, user email, base URL, "
                     + "and which is the default). No API keys are returned. Use the name or id with the "
                     + "`account` argument on any other tool to target a specific account (#519)."),
            tool("whoami",
                 "Report which CoderPad account this server is acting as: the account's display name, "
                     + "the user email it resolves to, the organization name, and the server base URL. "
                     + "Never returns the API key. Use this to confirm identity before answering "
                     + "organization-wide questions.",
                 properties: [account: accountSchema]),
            tool("list_pads", "List the account's pads (most recent first). Optional page and sort.",
                 properties: ["page": intSchema("1-based page number."),
                              "sort": stringSchema("Sort order, e.g. \"created_at\" or \"-created_at\"."),
                              account: accountSchema]),
            tool("get_pad", "Get a single pad by its slug/id.",
                 properties: ["pad": stringSchema("The pad's slug or id."), account: accountSchema],
                 required: ["pad"]),
            tool("list_questions", "List the account's question bank. Optional page and sort.",
                 properties: ["page": intSchema("1-based page number."),
                              "sort": stringSchema("Sort order."),
                              account: accountSchema]),
            tool("get_question", "Get a single question by its numeric id.",
                 properties: ["question": intSchema("The question's numeric id."), account: accountSchema],
                 required: ["question"]),
            tool("get_quota", "Get the organization's pad usage quota.",
                 properties: [account: accountSchema]),
            tool("get_organization", "Get the organization's teams and members.",
                 properties: [account: accountSchema])
        ]
    }

    /// The name of the optional account-selector argument shared by the per-account tools.
    private static let account = "account"

    /// Schema for the `account` argument: which configured account to target.
    private static var accountSchema: [String: Any] {
        stringSchema(
            "Optional. Which account to use, by its name or id (see list_accounts). "
                + "Defaults to the account selected in the app."
        )
    }

    /// Dispatches a tool call to its CoderPad endpoint, against the account selected by the
    /// optional `account` argument (defaulting to the app's current account, #519).
    static func run(name: String, arguments: [String: Any], directory: MCPAccountDirectory) async -> Outcome {
        // list_accounts is a directory-level query — it isn't scoped to one account.
        if name == "list_accounts" {
            return listAccounts(directory: directory)
        }

        guard let credentials = directory.resolve(string(arguments, account)) else {
            let available = directory.accounts.map(\.accountName).joined(separator: ", ")
            return Outcome(
                text: "No account matches \"\(string(arguments, account) ?? "")\". "
                    + "Available accounts: \(available). Use list_accounts to see their ids.",
                isError: true
            )
        }

        return await dispatch(name: name, arguments: arguments, credentials: credentials)
    }

    /// Runs one account-scoped tool against the resolved credentials. Split out of `run`
    /// so each stays within the cyclomatic-complexity budget.
    private static func dispatch(
        name: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        let key = credentials.apiKey
        let base = credentials.baseURL

        switch name {
        case "whoami":
            return await whoami(credentials: credentials)

        case "list_pads":
            return await get("/api/pads/", key: key, base: base, query: paging(arguments))

        case "get_pad":
            guard let pad = string(arguments, "pad") else { return missing("pad") }

            return await get("/api/pads/\(pad)", key: key, base: base)

        case "list_questions":
            return await get("/api/questions/", key: key, base: base, query: paging(arguments))

        case "get_question":
            guard let question = int(arguments, "question") else { return missing("question") }

            return await get("/api/questions/\(question)", key: key, base: base)

        case "get_quota":
            return await get("/api/quota", key: key, base: base)

        case "get_organization":
            return await get("/api/organization", key: key, base: base)

        default:
            return Outcome(text: "Unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - list_accounts (#519)

    /// Lists every configured account the server can act as — id, display name, resolved
    /// user email, base URL, and whether it's the current default — as JSON. API keys are
    /// deliberately never included.
    private static func listAccounts(directory: MCPAccountDirectory) -> Outcome {
        let currentID = directory.current?.id
        let list: [[String: Any]] = directory.accounts.map { account in
            [
                "id": account.id,
                "name": account.accountName,
                "user_email": account.userEmail,
                "base_url": account.baseURL.absoluteString,
                "is_current": account.id == currentID
            ]
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: ["accounts": list], options: [.prettyPrinted, .sortedKeys]
        ), let text = String(bytes: data, encoding: .utf8) else {
            return Outcome(text: "Could not encode the account list.", isError: true)
        }

        return Outcome(text: text, isError: false)
    }

    // MARK: - whoami (#518)

    /// Reports the acting account's identity as JSON: its display name and resolved user
    /// email (known locally, since the CoderPad API doesn't expose the key's owner), the
    /// server base URL, and the organization name (fetched from `/api/organization`). The
    /// API key is deliberately never included. If the org fetch fails, the local fields
    /// are still returned with a note, so `whoami` stays useful offline.
    private static func whoami(credentials: MCPCredentials) async -> Outcome {
        var info: [String: Any] = [
            "account_name": credentials.accountName,
            "user_email": credentials.userEmail,
            "base_url": credentials.baseURL.absoluteString
        ]

        let org = await get("/api/organization", key: credentials.apiKey, base: credentials.baseURL)
        if !org.isError,
           let data = org.text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["organization_name"] as? String {
            info["organization_name"] = name
        } else {
            info["organization_note"] = "Could not fetch the organization name from the API."
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: info, options: [.prettyPrinted, .sortedKeys]
        ), let text = String(bytes: data, encoding: .utf8) else {
            return Outcome(text: "Could not encode the account info.", isError: true)
        }

        return Outcome(text: text, isError: false)
    }

    // MARK: - HTTP

    /// Performs an authenticated GET and returns the raw JSON body verbatim, or an error
    /// outcome carrying the HTTP status / failure reason.
    private static func get(_ path: String,
                            key: String,
                            base: URL,
                            query: [URLQueryItem] = []) async -> Outcome {
        guard var components = URLComponents(url: base.appending(path: path),
                                             resolvingAgainstBaseURL: false) else {
            return Outcome(text: "Could not build a URL for \(path).", isError: true)
        }

        let items = query.filter { ($0.value ?? "").isEmpty == false }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else {
            return Outcome(text: "Could not build a URL for \(path).", isError: true)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(bytes: data, encoding: .utf8) ?? ""
            if (200 ..< 300).contains(status) {
                return Outcome(text: body, isError: false)
            }
            return Outcome(text: "HTTP \(status)\n\(body)", isError: true)
        } catch {
            return Outcome(text: "Request to \(path) failed: \(error.localizedDescription)", isError: true)
        }
    }

    private static func paging(_ arguments: [String: Any]) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if let page = int(arguments, "page") { query.append(URLQueryItem(name: "page", value: String(page))) }
        if let sort = string(arguments, "sort") { query.append(URLQueryItem(name: "sort", value: sort)) }
        return query
    }

    private static func missing(_ name: String) -> Outcome {
        Outcome(text: "Missing required argument: \(name)", isError: true)
    }

    // MARK: - Argument coercion

    /// Reads a string argument, tolerating a number sent where a string was expected.
    private static func string(_ arguments: [String: Any], _ name: String) -> String? {
        if let value = arguments[name] as? String, !value.isEmpty { return value }
        if let value = arguments[name] as? Int { return String(value) }
        return nil
    }

    /// Reads an integer argument, tolerating a numeric string.
    private static func int(_ arguments: [String: Any], _ name: String) -> Int? {
        if let value = arguments[name] as? Int { return value }
        if let text = arguments[name] as? String { return Int(text) }
        return nil
    }

    // MARK: - Tool / schema builders

    private static func tool(_ name: String,
                             _ description: String,
                             properties: [String: [String: Any]] = [:],
                             required: [String] = []) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": description, "inputSchema": schema]
    }

    private static func intSchema(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private static func stringSchema(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }
}
