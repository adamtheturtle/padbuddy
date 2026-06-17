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

// MARK: - CoderPad REST

private struct APIResponse {
    let status: Int
    let body: String
    var ok: Bool { (200..<300).contains(status) }
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

// MARK: - Server

let server = Server(
    name: "coderpad",
    version: "0.1.0",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: tools)
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "list_pads":
        return toolResult(await apiGet("/api/pads/", query: pagingQuery(params.arguments)))

    case "get_pad":
        guard let id = stringArgument(params.arguments, "id"), !id.isEmpty else {
            return missingArgument("id")
        }
        return toolResult(await apiGet("/api/pads/\(id)"))

    case "list_questions":
        return toolResult(await apiGet("/api/questions/", query: pagingQuery(params.arguments)))

    case "get_question":
        guard let id = intArgument(params.arguments, "id") else {
            return missingArgument("id (integer)")
        }
        return toolResult(await apiGet("/api/questions/\(id)"))

    case "get_quota":
        return toolResult(await apiGet("/api/quota"))

    case "get_organization":
        return toolResult(await apiGet("/api/organization"))

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
