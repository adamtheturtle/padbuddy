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

    /// Tool descriptors for `tools/list`, built from the shared catalog in CoderPadToolCore
    /// (#521) so each tool is defined once and appears identically here and in the standalone
    /// CLI. Screen tools appear only when configured; write tools (#502) only when opted in.
    static func all(allowWrites: Bool, screenEnabled: Bool) -> [[String: Any]] {
        coderPadToolDescriptors(screenEnabled: screenEnabled, writesEnabled: allowWrites)
    }

    /// The names of the write tools (#502), gated on the opt-in. From the shared catalog so
    /// the `run` gate and the `tools/list` filter can't drift apart.
    static let writeToolNames = coderPadWriteToolNames

    /// The name of the optional account-selector argument shared by the per-account tools.
    static let account = mcpAccountArgument

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
            if let ambiguous = ambiguousAccountMessage(arguments: arguments, directory: directory) {
                return Outcome(text: ambiguous, isError: true)
            }

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

    private static func ambiguousAccountMessage(arguments: [String: Any], directory: MCPAccountDirectory) -> String? {
        let selector = string(arguments, account)
        let ids = directory.ambiguousAccountIDs(for: selector)
        guard !ids.isEmpty else { return nil }

        return "Account selector \"\(selector ?? "")\" matches multiple accounts. "
            + "Use one of these account ids instead: \(ids.joined(separator: ", "))."
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

    /// Reads a string argument only when the key is present, preserving explicit empty
    /// strings for write tools that need to clear existing text fields.
    static func presentString(_ arguments: [String: Any], _ name: String) -> String? {
        guard arguments.keys.contains(name) else { return nil }

        if let value = arguments[name] as? String { return value }
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
}
