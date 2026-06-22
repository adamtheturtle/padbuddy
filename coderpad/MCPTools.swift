//
//  MCPTools.swift
//  coderpad
//
//  The read-only tool set exposed by the in-app MCP server (#402), mirroring the
//  standalone server from #393: each tool maps to one authenticated CoderPad GET and
//  returns the API's JSON verbatim, which keeps the server resilient to schema
//  additions and gives the assistant the richest representation.
//

import BuddyMCP
import Foundation

nonisolated enum MCPTools {
    /// The result of running a tool: the text handed back to the assistant, and whether
    /// it should be flagged as an error (e.g. an HTTP failure).
    struct Outcome {
        let text: String
        let isError: Bool
    }

    /// Tool descriptors for `tools/list`, as plain JSON objects. A fresh array is built
    /// per call (no shared state). The write tools (#502) are appended only when the user
    /// has opted in, so an assistant never even sees them otherwise.
    static func all(allowWrites: Bool, screenEnabled: Bool) -> [[String: Any]] {
        readTools
            + (screenEnabled ? screenTools : [])
            + (allowWrites ? writeTools : [])
    }

    /// The read-only tools, always available.
    private static var readTools: [[String: Any]] {
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
            tool("get_pad_code",
                 "Return just the code in a pad: each file with its filename, language, and "
                     + "contents (handles both legacy single-file pads and multi-file environments). "
                     + "Use this to read a candidate's code without the whole pad object.",
                 properties: ["pad": stringSchema("The pad's slug or id."),
                              "max_file_chars": intSchema("Optional. Truncate each file to this many characters."),
                              account: accountSchema],
                 required: ["pad"]),
            tool("count_pads",
                 "Count pads, optionally filtered, WITHOUT returning the records — one cheap "
                     + "call instead of paging every verbose record through the model. Served "
                     + "from PadBuddy's local cache when it's fresh (and offline), else paged "
                     + "live; the response's `source` field says which.",
                 properties: filterProperties.merging([account: accountSchema]) { _, new in new }),
            tool("aggregate_pads",
                 "Group pads by a field and return only the counts (not the records) — e.g. how "
                     + "many pads each owner has, over a large org, without blowing context. Uses "
                     + "PadBuddy's local cache when fresh (see the `source` field).",
                 properties: filterProperties.merging([
                     "group_by": stringSchema("Field to group by: owner, language, state, or month."),
                     account: accountSchema
                 ]) { _, new in new },
                 required: ["group_by"]),
            tool("list_pads_compact",
                 "Like list_pads but returns only id, title, owner_email, state, language, and "
                     + "created_at per pad, so far more rows fit per response.",
                 properties: ["page": intSchema("1-based page number."),
                              "sort": stringSchema("Sort order."),
                              account: accountSchema]),
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
        ] + questionReadTools
    }

    /// The names of the write tools (#502), gated on the opt-in. Kept as one set so the
    /// `run` gate and the `tools/list` filter can't drift apart.
    static let writeToolNames: Set<String> = [
        "create_pad", "update_pad", "create_question", "update_question"
    ]

    /// The name of the optional account-selector argument shared by the per-account tools.
    static let account = "account"

    /// Schema for the `account` argument: which configured account to target.
    static var accountSchema: [String: Any] {
        stringSchema(
            "Optional. Which account to use, by its name or id (see list_accounts). "
                + "Defaults to the account selected in the app."
        )
    }

    /// The owner/state/language filters shared by count_pads and aggregate_pads. The list
    /// API has no server-side filters, so these are applied in-process while paging.
    private static var filterProperties: [String: [String: Any]] {
        [
            "owner": stringSchema("Only pads whose owner_email matches this, case-insensitively."),
            "state": stringSchema("Only pads in this state (e.g. \"active\", \"ended\")."),
            "language": stringSchema("Only pads in this language (e.g. \"python\")."),
            "created_after": stringSchema(dateBoundDescription(bound: "on or after")),
            "created_before": stringSchema(dateBoundDescription(bound: "on or before"))
        ]
    }

    /// Description for a created_at date-range bound argument, shared by the pad and
    /// question filter schemas.
    static func dateBoundDescription(bound: String) -> String {
        "Only records created \(bound) this date. Accepts a month (\"2026-03\"), a date "
            + "(\"2026-03-01\"), or a full ISO8601 timestamp; inclusive at the given granularity."
    }

    /// Dispatches a tool call to its CoderPad endpoint, against the account selected by the
    /// optional `account` argument (defaulting to the app's current account, #519).
    static func run(name: String, arguments: [String: Any], directory: MCPAccountDirectory) async -> Outcome {
        // list_accounts is a directory-level query — it isn't scoped to one account.
        if name == "list_accounts" {
            return listAccounts(directory: directory)
        }

        // Write tools are gated on the explicit opt-in. Reject before resolving an account
        // so a disabled server gives the same clear message regardless of arguments (#502).
        if writeToolNames.contains(name), !directory.allowWrites {
            return Outcome(
                text: "Writing is turned off for this MCP server. To let it create or edit "
                    + "CoderPad content, turn on \"Allow the MCP server to make changes\" in "
                    + "PadBuddy's MCP settings, then restart your assistant.",
                isError: true
            )
        }

        guard let credentials = directory.resolve(string(arguments, account)) else {
            let available = directory.accounts.map(\.accountName).joined(separator: ", ")
            return Outcome(
                text: "No account matches \"\(string(arguments, account) ?? "")\". "
                    + "Available accounts: \(available). Use list_accounts to see their ids.",
                isError: true
            )
        }

        if writeToolNames.contains(name) {
            return await dispatchWrite(name: name, arguments: arguments, credentials: credentials)
        }
        if screenToolNames.contains(name) {
            return await dispatchScreen(name: name, arguments: arguments, credentials: credentials)
        }
        return await dispatch(name: name, arguments: arguments, credentials: credentials)
    }

    /// Runs one account-scoped tool against the resolved credentials. The tools needing
    /// an argument or assembly are handled here; the plain list/summary GETs delegate to
    /// `listOrSummary`, so each function stays within the cyclomatic-complexity budget.
    private static func dispatch(
        name: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        let key = credentials.apiKey
        let base = credentials.baseURL

        switch name {
        case "whoami":
            return await whoami(credentials: credentials)

        case "get_pad":
            guard let pad = string(arguments, "pad") else { return missing("pad") }

            return await getPadCacheBacked(pad: pad, credentials: credentials)

        case "get_pad_code":
            guard let pad = string(arguments, "pad") else { return missing("pad") }

            let maxChars = int(arguments, "max_file_chars")
            return await getPadCode(pad: pad, maxFileChars: maxChars, key: key, base: base)

        case "get_question":
            guard let question = int(arguments, "question") else { return missing("question") }

            return await getQuestionCacheBacked(id: question, credentials: credentials)

        default:
            return await padQuery(name: name, arguments: arguments, credentials: credentials)
        }
    }

    /// The pad count/aggregate/compact tools (#500), which page or project the pad list.
    /// Falls through to `listOrSummary` for the plain GETs. Takes the whole `credentials`
    /// because the count/aggregate tools also read the account's on-disk cache (#520),
    /// which is keyed by account id, not just the API key/base.
    private static func padQuery(
        name: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        let key = credentials.apiKey
        let base = credentials.baseURL

        switch name {
        case "count_pads":
            return await countPads(arguments: arguments, credentials: credentials)

        case "aggregate_pads":
            guard let groupBy = string(arguments, "group_by") else { return missing("group_by") }

            return await aggregatePads(groupBy: groupBy, arguments: arguments, credentials: credentials)

        case "list_pads_compact":
            return await listPadsCompact(arguments: arguments, key: key, base: base)

        default:
            return await questionQuery(name: name, arguments: arguments, credentials: credentials)
        }
    }

    /// The plain list/summary GET tools, which take no required argument. Internal (not
    /// private) so the question-query router in MCPTools+QuestionQuery can fall through to it.
    static func listOrSummary(
        name: String, arguments: [String: Any], key: String, base: URL
    ) async -> Outcome {
        switch name {
        case "list_pads":
            await get("/api/pads/", key: key, base: base, query: paging(arguments))

        case "list_questions":
            await get("/api/questions/", key: key, base: base, query: paging(arguments))

        case "get_quota":
            await get("/api/quota", key: key, base: base)

        case "get_organization":
            await get("/api/organization", key: key, base: base)

        default:
            Outcome(text: "Unknown tool: \(name)", isError: true)
        }
    }

    // MARK: - HTTP

    /// Performs an authenticated GET and returns the raw JSON body verbatim, or an error
    /// outcome carrying the HTTP status / failure reason.
    static func get(_ path: String,
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

    static func paging(_ arguments: [String: Any]) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if let page = int(arguments, "page") { query.append(URLQueryItem(name: "page", value: String(page))) }
        if let sort = string(arguments, "sort") { query.append(URLQueryItem(name: "sort", value: sort)) }
        return query
    }

    static func missing(_ name: String) -> Outcome {
        Outcome(text: "Missing required argument: \(name)", isError: true)
    }

    // MARK: - Argument coercion

    /// Reads a string argument, tolerating a number sent where a string was expected.
    static func string(_ arguments: [String: Any], _ name: String) -> String? {
        if let value = arguments[name] as? String, !value.isEmpty { return value }
        if let value = arguments[name] as? Int { return String(value) }
        return nil
    }

    /// Reads an integer argument, tolerating a numeric string.
    static func int(_ arguments: [String: Any], _ name: String) -> Int? {
        if let value = arguments[name] as? Int { return value }
        if let text = arguments[name] as? String { return Int(text) }
        return nil
    }

    /// Reads a boolean argument, tolerating the JSON strings "true"/"false".
    static func bool(_ arguments: [String: Any], _ name: String) -> Bool? {
        if let value = arguments[name] as? Bool { return value }
        if let text = arguments[name] as? String {
            if text == "true" { return true }
            if text == "false" { return false }
        }
        return nil
    }

    // MARK: - Tool / schema builders

    static func tool(_ name: String,
                     _ description: String,
                     properties: [String: [String: Any]] = [:],
                     required: [String] = [],
                     annotations: [String: Any] = [:]) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": properties]
        if !required.isEmpty { schema["required"] = required }
        var descriptor: [String: Any] = ["name": name, "description": description, "inputSchema": schema]
        if !annotations.isEmpty { descriptor["annotations"] = annotations }
        return descriptor
    }

    static func intSchema(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    static func stringSchema(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }
}
