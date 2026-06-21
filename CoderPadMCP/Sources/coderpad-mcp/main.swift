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

/// Client-side filters shared by the pad count/aggregate tools. Filtering happens
/// in this process while paging the list, since the CoderPad list API has no
/// server-side filter parameters.
private let padFilterProperties: [String: Value] = [
    "owner": property("string", "Only pads whose owner_email matches this, case-insensitively."),
    "state": property("string", "Only pads in this state (e.g. \"active\", \"ended\")."),
    "language": property("string", "Only pads in this language (e.g. \"python\").")
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
        name: "get_pad_code",
        description: "Return just the code for a pad: every file with its filename, language, and contents. Handles both legacy single-file pads (the pad's \"contents\") and multi-file environments (each pad_environment's \"file_contents\"). Use this to read or review a candidate's code without digging through the whole pad object.",
        inputSchema: objectSchema([
            "id": property("string", "The pad id / slug."),
            "max_file_chars": property(
                "integer",
                "Optional. Truncate each file's contents to at most this many characters (full file contents can be large). Omit for the complete contents."
            )
        ], required: ["id"])
    ),
    Tool(
        name: "count_pads",
        description: "Count pads, optionally filtered, WITHOUT returning the records. Pages the whole list internally and returns just the matched total — so \"how many pads match X\" is one cheap call instead of pulling every page of verbose JSON through the model.",
        inputSchema: objectSchema(padFilterProperties)
    ),
    Tool(
        name: "aggregate_pads",
        description: "Group pads by a field and return only the counts (not the records). Pages the whole list internally and tallies in this process. Use this for questions like \"how many pads does each owner have?\" over large orgs without blowing the assistant's context.",
        inputSchema: objectSchema(
            padFilterProperties.merging([
                "group_by": property(
                    "string",
                    "Field to group by: \"owner\" (owner_email), \"language\", \"state\", or \"month\" (created_at year-month)."
                )
            ]) { _, new in new },
            required: ["group_by"]
        )
    ),
    Tool(
        name: "list_pads_compact",
        description: "Like list_pads but returns only id, title, owner_email, state, language, and created_at per pad (dropping the verbose blob), so far more rows fit per response. Includes next_page and total for driving pagination.",
        inputSchema: objectSchema(pagingProperties)
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

    case "get_pad_code":
        guard let id = stringArgument(params.arguments, "id"), !id.isEmpty else {
            return missingArgument("id")
        }

        return await getPadCode(id: id, maxFileChars: intArgument(params.arguments, "max_file_chars"))

    case "count_pads":
        return await countPads(arguments: params.arguments)

    case "aggregate_pads":
        guard let groupBy = stringArgument(params.arguments, "group_by"), !groupBy.isEmpty else {
            return missingArgument("group_by")
        }

        return await aggregatePads(groupBy: groupBy, arguments: params.arguments)

    case "list_pads_compact":
        return await listPadsCompact(arguments: params.arguments)

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

// MARK: - get_pad_code

/// Parses a JSON object body into a dictionary, or nil if it isn't an object.
/// Used by get_pad_code so it can pull code fields out of the verbatim API JSON
/// without binding to a rigid Codable schema (keeping it resilient to additions).
private func jsonObject(_ body: String) -> [String: Any]? {
    guard let data = body.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    return object
}

/// Truncates a file body to `maxChars`, appending a marker noting how much was
/// dropped. A nil/non-positive limit returns the body unchanged.
private func truncate(_ body: String, to maxChars: Int?) -> String {
    guard let maxChars, maxChars > 0, body.count > maxChars else { return body }

    let dropped = body.count - maxChars
    return String(body.prefix(maxChars)) + "\n… [truncated, \(dropped) more characters]"
}

/// A handful of common language → file extension mappings, used only to synthesize
/// a filename for legacy single-file pads, which have no path of their own.
private let languageExtensions: [String: String] = [
    "python": "py", "python3": "py", "javascript": "js", "typescript": "ts",
    "java": "java", "ruby": "rb", "go": "go", "golang": "go", "c": "c",
    "cpp": "cpp", "c++": "cpp", "csharp": "cs", "c#": "cs", "php": "php",
    "swift": "swift", "kotlin": "kt", "rust": "rs", "sql": "sql",
    "scala": "scala", "r": "r", "perl": "pl", "bash": "sh", "shell": "sh"
]

/// Synthesizes `main.<ext>` for a file that has no path of its own (legacy
/// single-file pads). Falls back to the language name as the extension, then txt.
private func synthesizedFilename(language: String?) -> String {
    guard let language, !language.isEmpty else { return "main.txt" }

    let key = language.lowercased()
    return "main.\(languageExtensions[key] ?? key)"
}

/// Implements get_pad_code: fetch the pad, then assemble a compact { pad_id, title,
/// files: [{ filename, language, contents }] }. Multi-file environments
/// (pad_environment_ids → /api/pad_environments/<id> → file_contents) take
/// precedence; a legacy single-file pad's top-level "contents" is the fallback.
private func getPadCode(id: String, maxFileChars: Int?) async -> CallTool.Result {
    let padResponse = await apiGet("/api/pads/\(id)")
    guard padResponse.ok else { return toolResult(padResponse) }
    guard let pad = jsonObject(padResponse.body) else {
        return CallTool.Result(
            content: [.text(text: "Could not parse the pad response as JSON.", annotations: nil, _meta: nil)],
            isError: true
        )
    }

    var files: [[String: Any]] = []

    let environmentIDs = (pad["pad_environment_ids"] as? [Any])?
        .compactMap { ($0 as? Int) ?? Int("\($0)") } ?? []
    for environmentID in environmentIDs {
        let environmentResponse = await apiGet("/api/pad_environments/\(environmentID)")
        guard environmentResponse.ok, let environment = jsonObject(environmentResponse.body) else { continue }

        let environmentLanguage = environment["language"] as? String
        let fileContents = environment["file_contents"] as? [[String: Any]] ?? []
        for file in fileContents {
            let language = (file["language"] as? String) ?? environmentLanguage
            var entry: [String: Any] = [
                "filename": (file["path"] as? String) ?? synthesizedFilename(language: language),
                "contents": truncate(file["contents"] as? String ?? "", to: maxFileChars),
                "environment_id": environmentID
            ]
            if let language { entry["language"] = language }
            files.append(entry)
        }
    }

    // Legacy single-file representation: only when no environment files were found.
    if files.isEmpty, let contents = pad["contents"] as? String, !contents.isEmpty {
        let language = pad["language"] as? String
        var entry: [String: Any] = [
            "filename": synthesizedFilename(language: language),
            "contents": truncate(contents, to: maxFileChars)
        ]
        if let language { entry["language"] = language }
        files.append(entry)
    }

    let result: [String: Any] = [
        "pad_id": id,
        "title": pad["title"] as? String ?? "",
        "files": files
    ]
    guard let data = try? JSONSerialization.data(
        withJSONObject: result, options: [.prettyPrinted, .sortedKeys]
    ) else {
        return CallTool.Result(
            content: [.text(text: "Could not encode the pad code.", annotations: nil, _meta: nil)],
            isError: true
        )
    }

    return CallTool.Result(
        content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
        isError: nil
    )
}

// MARK: - count_pads / aggregate_pads / list_pads_compact (#500)

/// Safety cap on internal paging so a huge org (or a paging bug) can't loop
/// forever. At ~50 pads/page this covers 25k pads; if hit, the result reports it
/// as truncated rather than silently capping.
private let maxPadPagesToFetch = 500

/// At most this many groups are returned by aggregate_pads; if there are more, the
/// top ones by count are returned and the result flags that it was truncated.
private let maxAggregateGroups = 200

/// The accumulated result of paging the whole pad list internally.
private struct PadPageScan {
    var pads: [[String: Any]] = []
    var totalReported: Int?
    var pagesFetched = 0
    var truncated = false
    var error: APIResponse?
}

/// Interprets a `next_page` value (a string token, or an int in some responses);
/// nil means there are no more pages.
private func nextPageToken(_ value: Any?) -> String? {
    switch value {
    case let token as String: token.isEmpty ? nil : token
    case let number as Int: String(number)
    default: nil
    }
}

/// Pages `/api/pads/` from the first page following `next_page`, accumulating every
/// pad, so the count/aggregate tools can tally in-process and return a small answer
/// instead of streaming thousands of records through the model.
private func fetchAllPads() async -> PadPageScan {
    var scan = PadPageScan()
    var page: String?
    while scan.pagesFetched < maxPadPagesToFetch {
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: page)) }
        let response = await apiGet("/api/pads/", query: query)
        guard response.ok, let object = jsonObject(response.body) else {
            scan.error = response
            return scan
        }

        if scan.totalReported == nil { scan.totalReported = object["total"] as? Int }
        if let pads = object["pads"] as? [[String: Any]] { scan.pads.append(contentsOf: pads) }
        scan.pagesFetched += 1
        guard let next = nextPageToken(object["next_page"]) else { return scan }

        page = next
    }

    scan.truncated = true
    return scan
}

/// Whether a pad passes the optional owner/state/language filters (case-insensitive
/// exact match; an empty/absent filter always passes).
private func padMatches(_ pad: [String: Any], owner: String?, state: String?, language: String?) -> Bool {
    func equals(_ field: String, _ wanted: String?) -> Bool {
        guard let wanted, !wanted.isEmpty else { return true }

        return (pad[field] as? String)?.lowercased() == wanted.lowercased()
    }

    return equals("owner_email", owner) && equals("state", state) && equals("language", language)
}

/// Echoes the active filters back into a result, for clarity on what was counted.
private func filtersEcho(owner: String?, state: String?, language: String?) -> [String: Any] {
    var filters: [String: Any] = [:]
    if let owner, !owner.isEmpty { filters["owner"] = owner }
    if let state, !state.isEmpty { filters["state"] = state }
    if let language, !language.isEmpty { filters["language"] = language }
    return filters
}

/// Encodes a result dictionary as pretty JSON text.
private func jsonResult(_ object: [String: Any]) -> CallTool.Result {
    guard let data = try? JSONSerialization.data(
        withJSONObject: object, options: [.prettyPrinted, .sortedKeys]
    ) else {
        return CallTool.Result(
            content: [.text(text: "Could not encode the result.", annotations: nil, _meta: nil)],
            isError: true
        )
    }

    return CallTool.Result(
        content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)],
        isError: nil
    )
}

private func countPads(arguments: [String: Value]?) async -> CallTool.Result {
    let owner = stringArgument(arguments, "owner")
    let state = stringArgument(arguments, "state")
    let language = stringArgument(arguments, "language")

    let scan = await fetchAllPads()
    if let error = scan.error { return toolResult(error) }

    let matched = scan.pads.filter { padMatches($0, owner: owner, state: state, language: language) }
    var result: [String: Any] = [
        "matched": matched.count,
        "scanned": scan.pads.count,
        "pages_fetched": scan.pagesFetched,
        "truncated": scan.truncated
    ]
    if let total = scan.totalReported { result["total_reported_by_api"] = total }
    let filters = filtersEcho(owner: owner, state: state, language: language)
    if !filters.isEmpty { result["filters"] = filters }
    if scan.truncated {
        result["note"] = "Hit the internal page cap (\(maxPadPagesToFetch) pages); the count covers only the pads scanned."
    }

    return jsonResult(result)
}

private func aggregatePads(groupBy: String, arguments: [String: Value]?) async -> CallTool.Result {
    let field: String
    switch groupBy.lowercased() {
    case "owner", "owner_email": field = "owner_email"
    case "language": field = "language"
    case "state": field = "state"
    case "month", "created_at": field = "month"
    default:
        return CallTool.Result(
            content: [.text(
                text: "Unsupported group_by \"\(groupBy)\". Use owner, language, state, or month.",
                annotations: nil, _meta: nil
            )],
            isError: true
        )
    }

    let owner = stringArgument(arguments, "owner")
    let state = stringArgument(arguments, "state")
    let language = stringArgument(arguments, "language")

    let scan = await fetchAllPads()
    if let error = scan.error { return toolResult(error) }

    let matched = scan.pads.filter { padMatches($0, owner: owner, state: state, language: language) }
    var counts: [String: Int] = [:]
    for pad in matched {
        let key: String
        if field == "month" {
            let created = (pad["created_at"] as? String) ?? ""
            key = created.count >= 7 ? String(created.prefix(7)) : "unknown"
        } else {
            key = (pad[field] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        }
        counts[key, default: 0] += 1
    }

    // Sort by count descending, then key ascending, so the output is deterministic.
    let sorted = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
    let capped = Array(sorted.prefix(maxAggregateGroups))
    let groups: [[String: Any]] = capped.map { ["value": $0.key, "count": $0.value] }

    var result: [String: Any] = [
        "group_by": field,
        "matched": matched.count,
        "scanned": scan.pads.count,
        "distinct_groups": counts.count,
        "groups": groups,
        "pages_fetched": scan.pagesFetched,
        "truncated": scan.truncated
    ]
    let filters = filtersEcho(owner: owner, state: state, language: language)
    if !filters.isEmpty { result["filters"] = filters }
    if counts.count > capped.count {
        result["groups_truncated"] = true
        result["note"] = "Showing the top \(capped.count) of \(counts.count) groups by count."
    }
    if scan.truncated {
        result["page_cap_note"] = "Hit the internal page cap (\(maxPadPagesToFetch) pages); the aggregation covers only the pads scanned."
    }

    return jsonResult(result)
}

private func listPadsCompact(arguments: [String: Value]?) async -> CallTool.Result {
    let response = await apiGet("/api/pads/", query: pagingQuery(arguments))
    guard response.ok, let object = jsonObject(response.body) else { return toolResult(response) }

    let pads = (object["pads"] as? [[String: Any]]) ?? []
    let compact: [[String: Any]] = pads.map { pad in
        var row: [String: Any] = [:]
        for key in ["id", "title", "owner_email", "state", "language", "created_at"] where pad[key] != nil {
            row[key] = pad[key]
        }
        return row
    }

    var result: [String: Any] = ["pads": compact, "count": compact.count]
    if let next = object["next_page"], !(next is NSNull) { result["next_page"] = next }
    if let total = object["total"], !(total is NSNull) { result["total"] = total }

    return jsonResult(result)
}

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
