//
//  main.swift
//  coderpad-mcp
//
//  A local Model Context Protocol server for CoderPad (#393). It speaks MCP over
//  stdio and exposes a small set of read-only tools that fetch the signed-in
//  account's pads and questions straight from the CoderPad REST API, so an
//  MCP-aware assistant can answer questions about your interviews without the
//  macOS app being involved.
//
//  Configuration is via the environment, mirroring the app's dev key handling:
//    CODERPAD_API_KEY   (required)  a CoderPad API key — Settings → API on coderpad.io
//    CODERPAD_BASE_URL  (optional)  override for self-hosted / regional deployments
//                                   (defaults to https://app.coderpad.io)
//
//  Only read endpoints are exposed deliberately: a server an assistant can drive
//  should not be able to create, edit, or delete interview content.
//

import Foundation
import MCP

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Configuration

private let environment = ProcessInfo.processInfo.environment

private func requireAPIKey() -> String {
    guard let key = environment["CODERPAD_API_KEY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty
    else {
        FileHandle.standardError.write(Data(
            "coderpad-mcp: missing CODERPAD_API_KEY. Set it to a CoderPad API key (Settings -> API on coderpad.io).\n".utf8
        ))
        exit(1)
    }

    return key
}

private let apiKey = requireAPIKey()

private let baseURL: URL = {
    let raw = environment["CODERPAD_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let raw, !raw.isEmpty, let url = URL(string: raw) { return url }
    return URL(string: "https://app.coderpad.io")!
}()

/// CoderPad Screen (the assessment product) is a separate API with its own key and
/// host. Its tools are only offered when a Screen key is configured (#314).
///   CODERPAD_SCREEN_API_KEY  (optional)  enables the screen_* tools
///   CODERPAD_SCREEN_REGION   (optional)  "eu" for EU-hosted orgs, else US (default)
private let screenAPIKey: String? = {
    let raw = environment["CODERPAD_SCREEN_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (raw?.isEmpty == false) ? raw : nil
}()

private let screenBaseURL: URL = {
    let region = environment["CODERPAD_SCREEN_REGION"]?
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return region == "eu" ? URL(string: "https://www.codingame.eu")! : URL(string: "https://www.codingame.com")!
}()

private let screenAPIPrefix = "/assessment/api/v1.1"

// MARK: - CoderPad REST

private struct APIResponse {
    let status: Int
    let body: String
    var ok: Bool {
        (200 ..< 300).contains(status)
    }
}

/// Performs an authenticated GET and returns the status and raw JSON body. The
/// body is passed through verbatim to the MCP client rather than decoded — the
/// CoderPad API's JSON is already the most useful representation for an assistant,
/// and passing it through keeps this server resilient to schema additions.
private func apiGet(_ path: String, query: [URLQueryItem] = []) async -> APIResponse {
    guard var comps = URLComponents(
        url: baseURL.appending(path: path), resolvingAgainstBaseURL: false
    ) else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }

    let items = query.filter { ($0.value ?? "").isEmpty == false }
    if !items.isEmpty { comps.queryItems = items }
    guard let url = comps.url else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return APIResponse(status: status, body: String(decoding: data, as: UTF8.self))
    } catch {
        return APIResponse(status: 0, body: "Request to \(path) failed: \(error.localizedDescription)")
    }
}

private func toolResult(_ response: APIResponse) -> CallTool.Result {
    let text = response.ok ? response.body : "HTTP \(response.status)\n\(response.body)"
    return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)], isError: response.ok ? nil : true)
}

/// An authenticated GET against the CoderPad Screen API, which uses an `API-Key`
/// header (not Bearer) and its own host + version prefix. Returns the JSON body
/// verbatim, mirroring `apiGet`.
private func screenGet(_ path: String, query: [URLQueryItem] = []) async -> APIResponse {
    guard let key = screenAPIKey else {
        return APIResponse(
            status: 0,
            body: "Screen is not configured. Set CODERPAD_SCREEN_API_KEY to enable the screen_* tools."
        )
    }
    guard var comps = URLComponents(
        url: screenBaseURL.appending(path: screenAPIPrefix + path), resolvingAgainstBaseURL: false
    ) else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }

    let items = query.filter { ($0.value ?? "").isEmpty == false }
    if !items.isEmpty { comps.queryItems = items }
    guard let url = comps.url else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }

    var request = URLRequest(url: url)
    request.setValue(key, forHTTPHeaderField: "API-Key")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return APIResponse(status: status, body: String(decoding: data, as: UTF8.self))
    } catch {
        return APIResponse(status: 0, body: "Request to \(path) failed: \(error.localizedDescription)")
    }
}

// MARK: - Argument helpers

private func stringArgument(_ arguments: [String: Value]?, _ key: String) -> String? {
    switch arguments?[key] {
    case let .string(value): value
    case let .int(value): String(value)
    case let .double(value): String(value)
    default: nil
    }
}

private func intArgument(_ arguments: [String: Value]?, _ key: String) -> Int? {
    switch arguments?[key] {
    case let .int(value): value
    case let .double(value): Int(value)
    case let .string(value): Int(value)
    default: nil
    }
}

// MARK: - Tool schemas

private func property(_ type: String, _ description: String) -> Value {
    .object(["type": .string(type), "description": .string(description)])
}

private func objectSchema(_ properties: [String: Value] = [:], required: [String] = []) -> Value {
    var schema: [String: Value] = ["type": .string("object"), "properties": .object(properties)]
    if !required.isEmpty { schema["required"] = .array(required.map { .string($0) }) }
    return .object(schema)
}

private let pagingProperties: [String: Value] = [
    "page": property(
        "integer",
        "1-based page number. The API returns up to 50 items per page; the response includes \"next_page\" when more remain."
    ),
    "sort": property("string", "Optional sort field accepted by the CoderPad API (e.g. \"created_at\").")
]

private let tools: [Tool] = [
    Tool(
        name: "list_pads",
        description: "List the organization's pads (interview sessions), paginated. Returns the raw CoderPad API JSON, including next_page and total.",
        inputSchema: objectSchema(pagingProperties)
    ),
    Tool(
        name: "get_pad",
        description: "Fetch a single pad by its id (slug), with its full detail.",
        inputSchema: objectSchema(["id": property("string", "The pad id / slug.")], required: ["id"])
    ),
    Tool(
        name: "list_questions",
        description: "List the organization's question bank, paginated. Returns the raw CoderPad API JSON, including next_page and total.",
        inputSchema: objectSchema(pagingProperties)
    ),
    Tool(
        name: "get_question",
        description: "Fetch a single question by its numeric id, with its full detail.",
        inputSchema: objectSchema(["id": property("integer", "The numeric question id.")], required: ["id"])
    ),
    Tool(
        name: "get_quota",
        description: "Fetch the account's pad quota usage.",
        inputSchema: objectSchema()
    ),
    Tool(
        name: "get_organization",
        description: "Fetch the organization directory (teams and members).",
        inputSchema: objectSchema()
    )
]

/// CoderPad Screen (assessments) tools, offered only when a Screen key is set.
private let screenTools: [Tool] = [
    Tool(
        name: "screen_list_campaigns",
        description: "List the organization's CoderPad Screen assessment campaigns.",
        inputSchema: objectSchema()
    ),
    Tool(
        name: "screen_list_tests",
        description: "List CoderPad Screen test sessions (offset-paginated). The response's pagination.nextStart / hasMoreItems drive paging.",
        inputSchema: objectSchema([
            "campaignId": property("integer", "Only tests in this campaign."),
            "candidateEmail": property("string", "Only tests for this candidate email."),
            "start": property("integer", "Offset to start from (use pagination.nextStart from a prior call)."),
            "limit": property("integer", "Maximum number of tests to return.")
        ])
    ),
    Tool(
        name: "screen_get_test",
        description: "Fetch one CoderPad Screen test session (status and, once finished, its report) by numeric id.",
        inputSchema: objectSchema(["id": property("integer", "The numeric test-session id.")], required: ["id"])
    )
]

/// The tools to advertise: the Screen ones appear only when Screen is configured,
/// so a client without a Screen key isn't offered tools it can't use.
private func availableTools() -> [Tool] {
    screenAPIKey == nil ? tools : tools + screenTools
}

// MARK: - Server

let server = Server(
    name: "coderpad",
    version: "0.1.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: availableTools())
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "list_pads":
        return await toolResult(apiGet("/api/pads/", query: pagingQuery(params.arguments)))

    case "get_pad":
        guard let id = stringArgument(params.arguments, "id"), !id.isEmpty else {
            return missingArgument("id")
        }

        return await toolResult(apiGet("/api/pads/\(id)"))

    case "list_questions":
        return await toolResult(apiGet("/api/questions/", query: pagingQuery(params.arguments)))

    case "get_question":
        guard let id = intArgument(params.arguments, "id") else {
            return missingArgument("id (integer)")
        }

        return await toolResult(apiGet("/api/questions/\(id)"))

    case "get_quota":
        return await toolResult(apiGet("/api/quota"))

    case "get_organization":
        return await toolResult(apiGet("/api/organization"))

    case "screen_list_campaigns":
        return await toolResult(screenGet("/campaigns"))

    case "screen_list_tests":
        var query: [URLQueryItem] = []
        if let campaign = intArgument(params.arguments, "campaignId") {
            query.append(URLQueryItem(name: "campaignId", value: String(campaign)))
        }
        if let email = stringArgument(params.arguments, "candidateEmail") {
            query.append(URLQueryItem(name: "candidateEmail", value: email))
        }
        if let start = intArgument(params.arguments, "start") {
            query.append(URLQueryItem(name: "start", value: String(start)))
        }
        if let limit = intArgument(params.arguments, "limit") {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return await toolResult(screenGet("/tests", query: query))

    case "screen_get_test":
        guard let id = intArgument(params.arguments, "id") else {
            return missingArgument("id (integer)")
        }

        return await toolResult(screenGet("/tests/\(id)"))

    default:
        return CallTool.Result(
            content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

private func pagingQuery(_ arguments: [String: Value]?) -> [URLQueryItem] {
    var query: [URLQueryItem] = []
    if let page = intArgument(arguments, "page") { query.append(URLQueryItem(name: "page", value: String(page))) }
    if let sort = stringArgument(arguments, "sort") { query.append(URLQueryItem(name: "sort", value: sort)) }
    return query
}

private func missingArgument(_ name: String) -> CallTool.Result {
    CallTool.Result(
        content: [.text(text: "Missing required argument: \(name)", annotations: nil, _meta: nil)],
        isError: true
    )
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
