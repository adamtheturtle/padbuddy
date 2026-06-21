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
            tool("list_pads", "List the account's pads (most recent first). Optional page and sort.",
                 properties: ["page": intSchema("1-based page number."),
                              "sort": stringSchema("Sort order, e.g. \"created_at\" or \"-created_at\".")]),
            tool("get_pad", "Get a single pad by its slug/id.",
                 properties: ["pad": stringSchema("The pad's slug or id.")],
                 required: ["pad"]),
            tool("list_questions", "List the account's question bank. Optional page and sort.",
                 properties: ["page": intSchema("1-based page number."),
                              "sort": stringSchema("Sort order.")]),
            tool("get_question", "Get a single question by its numeric id.",
                 properties: ["question": intSchema("The question's numeric id.")],
                 required: ["question"]),
            tool("get_quota", "Get the organization's pad usage quota."),
            tool("get_organization", "Get the organization's teams and members.")
        ]
    }

    /// Dispatches a tool call to its CoderPad endpoint.
    static func run(name: String, arguments: [String: Any], credentials: MCPCredentials) async -> Outcome {
        let key = credentials.apiKey
        let base = credentials.baseURL

        switch name {
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
