//
//  main.swift
//  coderpad-mcp
//
//  A local Model Context Protocol server for CoderPad (#393). It speaks MCP over
//  stdio and exposes a small set of tools that fetch the signed-in account's pads and
//  questions straight from the CoderPad REST API, so an MCP-aware assistant can answer
//  questions about your interviews without the macOS app being involved.
//
//  This file is the thin executable: it reads configuration from the environment,
//  makes the REST calls, and wires up the stdio server. The network-free logic
//  (argument coercion, tool schemas, and the pad code/count/aggregate transforms)
//  lives in the CoderPadMCPCore library so it can be unit-tested (#522).
//
//  Configuration is via the environment, mirroring the app's dev key handling:
//    CODERPAD_API_KEY   (required)  a CoderPad API key — Settings → API on coderpad.io
//    CODERPAD_BASE_URL  (optional)  override for self-hosted / regional deployments
//                                   (defaults to https://app.coderpad.io)
//
//  Read tools are always available. Write tools (create/edit) are OFF unless
//  CODERPAD_MCP_ALLOW_WRITES is set — a deliberate opt-in (#502). There is no delete
//  tool: deletion stays a human action in the app.
//

import CoderPadMCPCore
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

/// Write tools (create/edit) are OFF by default — reads are always available. Set
/// `CODERPAD_MCP_ALLOW_WRITES` to a truthy value (1/true/yes/on) to advertise and
/// enable them. This mirrors the in-app server's separate "allow changes" opt-in
/// (#502): enabling the server doesn't grant write access; this flag does.
private let allowWrites: Bool = {
    let raw = environment["CODERPAD_MCP_ALLOW_WRITES"]?
        .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["1", "true", "yes", "on"].contains(raw)
}()

// MARK: - CoderPad REST

/// Performs an authenticated GET and returns the status and raw JSON body.
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

/// Performs an authenticated write (POST/PUT) with a JSON body and returns the raw
/// response, mirroring `apiGet`. Used only by the write tools, which are themselves
/// gated behind `allowWrites`.
private func apiSend(_ method: String, _ path: String, body: [String: Any]) async -> APIResponse {
    guard let url = URLComponents(
        url: baseURL.appending(path: path), resolvingAgainstBaseURL: false
    )?.url else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }
    guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
        return APIResponse(status: 0, body: "Could not encode the request body.")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = payload
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return APIResponse(status: status, body: String(decoding: data, as: UTF8.self))
    } catch {
        return APIResponse(status: 0, body: "Request to \(path) failed: \(error.localizedDescription)")
    }
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

// MARK: - Result helpers

private func missingArgument(_ name: String) -> CallTool.Result {
    CallTool.Result(
        content: [.text(text: "Missing required argument: \(name)", annotations: nil, _meta: nil)],
        isError: true
    )
}

private func writesDisabled() -> CallTool.Result {
    CallTool.Result(
        content: [.text(
            text: "Writes are disabled. Set CODERPAD_MCP_ALLOW_WRITES=1 to enable the create/edit tools.",
            annotations: nil, _meta: nil
        )],
        isError: true
    )
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

private func pagingQuery(_ arguments: [String: Value]?) -> [URLQueryItem] {
    var query: [URLQueryItem] = []
    if let page = intArgument(arguments, "page") { query.append(URLQueryItem(name: "page", value: String(page))) }
    if let sort = stringArgument(arguments, "sort") { query.append(URLQueryItem(name: "sort", value: sort)) }
    return query
}

// MARK: - Tools advertised here

/// The tools to advertise, given this process's Screen / writes configuration.
private func advertisedTools() -> [Tool] {
    availableTools(screenEnabled: screenAPIKey != nil, writesEnabled: allowWrites)
}

// MARK: - Server

let server = Server(
    name: "PadBuddy",
    version: "0.1.0",
    capabilities: .init(
        prompts: .init(listChanged: false),
        resources: .init(subscribe: false, listChanged: false),
        tools: .init(listChanged: false)
    )
)

await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: advertisedTools())
}

// MARK: - Prompts (#517)

await server.withMethodHandler(ListPrompts.self) { _ in
    ListPrompts.Result(prompts: interviewPrompts)
}

await server.withMethodHandler(GetPrompt.self) { params in
    do {
        return try renderPrompt(name: params.name, arguments: params.arguments)
    } catch let PromptError.unknownPrompt(name) {
        throw MCPError.invalidParams("Unknown prompt: \(name)")
    } catch let PromptError.missingArgument(name) {
        throw MCPError.invalidParams("Missing required argument: \(name)")
    }
}

// MARK: - Resources (#517)

await server.withMethodHandler(ListResources.self) { _ in
    ListResources.Result(resources: staticResources)
}

await server.withMethodHandler(ListResourceTemplates.self) { _ in
    ListResourceTemplates.Result(templates: resourceTemplates)
}

await server.withMethodHandler(ReadResource.self) { params in
    guard let request = parseResourceURI(params.uri) else {
        throw MCPError.invalidParams("Unknown resource URI: \(params.uri)")
    }

    return try await readResource(request, uri: params.uri)
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "whoami":
        return await whoami()

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

        return await aggregatePadsTool(groupBy: groupBy, arguments: params.arguments)

    case "list_pads_compact":
        return await listPadsCompact(arguments: params.arguments)

    case "list_questions":
        return await toolResult(apiGet("/api/questions/", query: pagingQuery(params.arguments)))

    case "get_question":
        guard let id = intArgument(params.arguments, "id") else {
            return missingArgument("id (integer)")
        }

        return await toolResult(apiGet("/api/questions/\(id)"))

    case "count_questions":
        return await countQuestions(arguments: params.arguments)

    case "aggregate_questions":
        guard let groupBy = stringArgument(params.arguments, "group_by"), !groupBy.isEmpty else {
            return missingArgument("group_by")
        }

        return await aggregateQuestionsTool(groupBy: groupBy, arguments: params.arguments)

    case "list_questions_compact":
        return await listQuestionsCompact(arguments: params.arguments)

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

    case "create_pad":
        guard allowWrites else { return writesDisabled() }

        return await createPad(arguments: params.arguments)

    case "update_pad":
        guard allowWrites else { return writesDisabled() }
        guard let id = stringArgument(params.arguments, "id"), !id.isEmpty else {
            return missingArgument("id")
        }

        return await updatePad(id: id, arguments: params.arguments)

    case "create_question":
        guard allowWrites else { return writesDisabled() }
        guard let title = optionalString(params.arguments, "title") else {
            return missingArgument("title")
        }

        return await createQuestion(title: title, arguments: params.arguments)

    case "update_question":
        guard allowWrites else { return writesDisabled() }
        guard let id = intArgument(params.arguments, "id") else {
            return missingArgument("id (integer)")
        }

        return await updateQuestion(id: id, arguments: params.arguments)

    default:
        return CallTool.Result(
            content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

// MARK: - whoami (#518)

/// Reports which account/org this server acts as, without the API key: the org name
/// (fetched from `/api/organization`), the base URL, and whether Screen and writes are
/// enabled. The standalone server is single-key by env var, so it has no account name
/// or resolved user email to report (unlike the in-app server).
private func whoami() async -> CallTool.Result {
    var info: [String: Any] = [
        "base_url": baseURL.absoluteString,
        "screen_configured": screenAPIKey != nil,
        "writes_enabled": allowWrites
    ]

    let org = await apiGet("/api/organization")
    if org.ok, let object = jsonObject(org.body), let name = object["organization_name"] as? String {
        info["organization_name"] = name
    } else {
        info["organization_note"] = "Could not fetch the organization name from the API."
    }

    return jsonResult(info)
}

// MARK: - get_pad_code (#499)

/// Fetches the pad and each of its environments and assembles the compact code JSON
/// via the pure `padCodePayload` in the core library. Throws `MCPError` on an HTTP or
/// parse failure so both the tool and the resource reader can surface it.
private func padCodeJSON(id: String, maxFileChars: Int?) async throws -> String {
    let padResponse = await apiGet("/api/pads/\(id)")
    guard padResponse.ok else {
        throw MCPError.internalError("HTTP \(padResponse.status)\n\(padResponse.body)")
    }
    guard let pad = jsonObject(padResponse.body) else {
        throw MCPError.internalError("Could not parse the pad response as JSON.")
    }

    var environments: [PadEnvironment] = []
    for environmentID in environmentIDs(in: pad) {
        let environmentResponse = await apiGet("/api/pad_environments/\(environmentID)")
        guard environmentResponse.ok, let object = jsonObject(environmentResponse.body) else { continue }

        environments.append(PadEnvironment(id: environmentID, object: object))
    }

    let payload = padCodePayload(id: id, pad: pad, environments: environments, maxFileChars: maxFileChars)
    guard let data = try? JSONSerialization.data(
        withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
    ) else {
        throw MCPError.internalError("Could not encode the pad code.")
    }

    return String(decoding: data, as: UTF8.self)
}

private func getPadCode(id: String, maxFileChars: Int?) async -> CallTool.Result {
    do {
        let json = try await padCodeJSON(id: id, maxFileChars: maxFileChars)
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)], isError: nil)
    } catch {
        return CallTool.Result(
            content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

// MARK: - Resource reads (#517)

/// Fetches the JSON behind a parsed resource URI and returns it as the resource's
/// contents. Throws `MCPError` on failure so the client gets a proper JSON-RPC error.
private func readResource(_ request: ResourceRequest, uri: String) async throws -> ReadResource.Result {
    func jsonResource(_ path: String) async throws -> ReadResource.Result {
        let response = await apiGet(path)
        guard response.ok else {
            throw MCPError.internalError("HTTP \(response.status) reading \(uri)\n\(response.body)")
        }

        return ReadResource.Result(contents: [.text(response.body, uri: uri, mimeType: "application/json")])
    }

    switch request {
    case .quota: return try await jsonResource("/api/quota")
    case .organization: return try await jsonResource("/api/organization")
    case let .pad(id): return try await jsonResource("/api/pads/\(id)")
    case let .question(id): return try await jsonResource("/api/questions/\(id)")
    case let .padCode(id):
        let json = try await padCodeJSON(id: id, maxFileChars: nil)
        return ReadResource.Result(contents: [.text(json, uri: uri, mimeType: "application/json")])
    }
}

// MARK: - count_pads / aggregate_pads / list_pads_compact (#500)

/// Safety cap on internal paging so a huge org (or a paging bug) can't loop forever.
/// At ~50 pads/page this covers 25k pads; if hit, the result reports it as truncated
/// rather than silently capping.
private let maxPadPagesToFetch = 500

/// At most this many groups are returned by aggregate_pads; if there are more, the top
/// ones by count are returned and the result flags that it was truncated.
private let maxAggregateGroups = 200

/// The accumulated result of paging the whole pad list internally.
private struct PadPageScan {
    var pads: [[String: Any]] = []
    var totalReported: Int?
    var pagesFetched = 0
    var truncated = false
    var error: APIResponse?
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

private func countPads(arguments: [String: Value]?) async -> CallTool.Result {
    let owner = stringArgument(arguments, "owner")
    let state = stringArgument(arguments, "state")
    let language = stringArgument(arguments, "language")
    let after = stringArgument(arguments, "created_after")
    let before = stringArgument(arguments, "created_before")

    let scan = await fetchAllPads()
    if let error = scan.error { return toolResult(error) }

    let matched = scan.pads.filter {
        padMatches($0, owner: owner, state: state, language: language)
            && withinDateRange($0, after: after, before: before)
    }
    var result: [String: Any] = [
        "matched": matched.count,
        "scanned": scan.pads.count,
        "pages_fetched": scan.pagesFetched,
        "truncated": scan.truncated
    ]
    if let total = scan.totalReported { result["total_reported_by_api"] = total }
    var filters = filtersEcho(owner: owner, state: state, language: language)
    addDateFilters(&filters, after: after, before: before)
    if !filters.isEmpty { result["filters"] = filters }
    if scan.truncated {
        result["note"] = "Hit the internal page cap (\(maxPadPagesToFetch) pages); the count covers only the pads scanned."
    }

    return jsonResult(result)
}

private func aggregatePadsTool(groupBy: String, arguments: [String: Value]?) async -> CallTool.Result {
    guard let field = aggregateField(for: groupBy) else {
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
    let after = stringArgument(arguments, "created_after")
    let before = stringArgument(arguments, "created_before")

    let scan = await fetchAllPads()
    if let error = scan.error { return toolResult(error) }

    let matched = scan.pads.filter {
        padMatches($0, owner: owner, state: state, language: language)
            && withinDateRange($0, after: after, before: before)
    }
    let counts = aggregateCounts(pads: matched, field: field)
    let capped = topGroups(counts, limit: maxAggregateGroups)
    let groups: [[String: Any]] = capped.map { ["value": $0.value, "count": $0.count] }

    var result: [String: Any] = [
        "group_by": field,
        "matched": matched.count,
        "scanned": scan.pads.count,
        "distinct_groups": counts.count,
        "groups": groups,
        "pages_fetched": scan.pagesFetched,
        "truncated": scan.truncated
    ]
    var filters = filtersEcho(owner: owner, state: state, language: language)
    addDateFilters(&filters, after: after, before: before)
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
    let compact = compactPads(pads)

    var result: [String: Any] = ["pads": compact, "count": compact.count]
    if let next = object["next_page"], !(next is NSNull) { result["next_page"] = next }
    if let total = object["total"], !(total is NSNull) { result["total"] = total }

    return jsonResult(result)
}

// MARK: - count_questions / aggregate_questions / list_questions_compact (#500)

/// The accumulated result of paging the whole question bank internally.
private struct QuestionPageScan {
    var questions: [[String: Any]] = []
    var totalReported: Int?
    var pagesFetched = 0
    var truncated = false
    var error: APIResponse?
}

/// Pages `/api/questions/` from the first page following `next_page`, accumulating every
/// question, so the count/aggregate tools can tally in-process and return a small answer
/// instead of streaming thousands of records through the model.
private func fetchAllQuestions() async -> QuestionPageScan {
    var scan = QuestionPageScan()
    var page: String?
    while scan.pagesFetched < maxPadPagesToFetch {
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: page)) }
        let response = await apiGet("/api/questions/", query: query)
        guard response.ok, let object = jsonObject(response.body) else {
            scan.error = response
            return scan
        }

        if scan.totalReported == nil { scan.totalReported = object["total"] as? Int }
        if let questions = object["questions"] as? [[String: Any]] { scan.questions.append(contentsOf: questions) }
        scan.pagesFetched += 1
        guard let next = nextPageToken(object["next_page"]) else { return scan }

        page = next
    }

    scan.truncated = true
    return scan
}

private func countQuestions(arguments: [String: Value]?) async -> CallTool.Result {
    let owner = stringArgument(arguments, "owner")
    let author = stringArgument(arguments, "author")
    let language = stringArgument(arguments, "language")
    let type = stringArgument(arguments, "type")
    let after = stringArgument(arguments, "created_after")
    let before = stringArgument(arguments, "created_before")

    let scan = await fetchAllQuestions()
    if let error = scan.error { return toolResult(error) }

    let matched = scan.questions.filter {
        questionMatches($0, owner: owner, author: author, language: language, type: type)
            && withinDateRange($0, after: after, before: before)
    }
    var result: [String: Any] = [
        "matched": matched.count,
        "scanned": scan.questions.count,
        "pages_fetched": scan.pagesFetched,
        "truncated": scan.truncated
    ]
    if let total = scan.totalReported { result["total_reported_by_api"] = total }
    var filters = questionFiltersEcho(owner: owner, author: author, language: language, type: type)
    addDateFilters(&filters, after: after, before: before)
    if !filters.isEmpty { result["filters"] = filters }
    if scan.truncated {
        result["note"] = "Hit the internal page cap (\(maxPadPagesToFetch) pages); the count covers only the questions scanned."
    }

    return jsonResult(result)
}

private func aggregateQuestionsTool(groupBy: String, arguments: [String: Value]?) async -> CallTool.Result {
    guard let field = questionAggregateField(for: groupBy) else {
        return CallTool.Result(
            content: [.text(
                text: "Unsupported group_by \"\(groupBy)\". Use owner, author, language, type, or month.",
                annotations: nil, _meta: nil
            )],
            isError: true
        )
    }

    let owner = stringArgument(arguments, "owner")
    let author = stringArgument(arguments, "author")
    let language = stringArgument(arguments, "language")
    let type = stringArgument(arguments, "type")
    let after = stringArgument(arguments, "created_after")
    let before = stringArgument(arguments, "created_before")

    let scan = await fetchAllQuestions()
    if let error = scan.error { return toolResult(error) }

    let matched = scan.questions.filter {
        questionMatches($0, owner: owner, author: author, language: language, type: type)
            && withinDateRange($0, after: after, before: before)
    }
    let counts = aggregateCounts(pads: matched, field: field)
    let capped = topGroups(counts, limit: maxAggregateGroups)
    let groups: [[String: Any]] = capped.map { ["value": $0.value, "count": $0.count] }

    var result: [String: Any] = [
        "group_by": field,
        "matched": matched.count,
        "scanned": scan.questions.count,
        "distinct_groups": counts.count,
        "groups": groups,
        "pages_fetched": scan.pagesFetched,
        "truncated": scan.truncated
    ]
    var filters = questionFiltersEcho(owner: owner, author: author, language: language, type: type)
    addDateFilters(&filters, after: after, before: before)
    if !filters.isEmpty { result["filters"] = filters }
    if counts.count > capped.count {
        result["groups_truncated"] = true
        result["note"] = "Showing the top \(capped.count) of \(counts.count) groups by count."
    }
    if scan.truncated {
        result["page_cap_note"] = "Hit the internal page cap (\(maxPadPagesToFetch) pages); the aggregation covers only the questions scanned."
    }

    return jsonResult(result)
}

private func listQuestionsCompact(arguments: [String: Value]?) async -> CallTool.Result {
    let response = await apiGet("/api/questions/", query: pagingQuery(arguments))
    guard response.ok, let object = jsonObject(response.body) else { return toolResult(response) }

    let questions = (object["questions"] as? [[String: Any]]) ?? []
    let compact = compactQuestions(questions)

    var result: [String: Any] = ["questions": compact, "count": compact.count]
    if let next = object["next_page"], !(next is NSNull) { result["next_page"] = next }
    if let total = object["total"], !(total is NSNull) { result["total"] = total }

    return jsonResult(result)
}

// MARK: - Write tools (#502, gated behind allowWrites)

private func createPad(arguments: [String: Value]?) async -> CallTool.Result {
    var body: [String: Any] = [:]
    if let title = optionalString(arguments, "title") { body["title"] = title }
    if let language = optionalString(arguments, "language") { body["language"] = language }
    if let owner = optionalString(arguments, "owner_email") { body["owner_email"] = owner }
    if let contents = optionalString(arguments, "contents") { body["contents"] = contents }
    if let notes = optionalString(arguments, "notes") { body["notes"] = notes }
    if let questionID = intArgument(arguments, "question_id") { body["question_id"] = questionID }
    if let teamID = optionalString(arguments, "team_id") { body["team_id"] = teamID }

    return await toolResult(apiSend("POST", "/api/pads/", body: body))
}

private func updatePad(id: String, arguments: [String: Value]?) async -> CallTool.Result {
    var body: [String: Any] = [:]
    if let title = optionalString(arguments, "title") { body["title"] = title }
    if let notes = optionalString(arguments, "notes") { body["notes"] = notes }
    if let owner = optionalString(arguments, "owner_email") { body["owner_email"] = owner }
    if let language = optionalString(arguments, "language") { body["language"] = language }
    guard !body.isEmpty else {
        return missingArgument("at least one of title / notes / owner_email / language")
    }

    return await toolResult(apiSend("PUT", "/api/pads/\(id)", body: body))
}

private func createQuestion(title: String, arguments: [String: Value]?) async -> CallTool.Result {
    var question: [String: Any] = ["title": title]
    if let language = optionalString(arguments, "language") { question["language"] = language }
    var body: [String: Any] = ["question": question]
    if let description = optionalString(arguments, "description") { body["description"] = description }
    if let solution = optionalString(arguments, "solution") { body["solution"] = solution }
    if let contents = optionalString(arguments, "contents") { body["contents"] = contents }

    return await toolResult(apiSend("POST", "/api/questions/", body: body))
}

private func updateQuestion(id: Int, arguments: [String: Value]?) async -> CallTool.Result {
    var question: [String: Any] = [:]
    if let title = optionalString(arguments, "title") { question["title"] = title }
    if let language = optionalString(arguments, "language") { question["language"] = language }
    var body: [String: Any] = [:]
    if !question.isEmpty { body["question"] = question }
    if let description = optionalString(arguments, "description") { body["description"] = description }
    if let solution = optionalString(arguments, "solution") { body["solution"] = solution }
    if let contents = optionalString(arguments, "contents") { body["contents"] = contents }
    guard !body.isEmpty else {
        return missingArgument("at least one of title / language / description / solution / contents")
    }

    return await toolResult(apiSend("PUT", "/api/questions/\(id)", body: body))
}

// MARK: - Run

let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
