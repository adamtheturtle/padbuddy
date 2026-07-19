//
//  main.swift
//  coderpad-mcp
//
//  A local Model Context Protocol server for CoderPad (#393). It speaks MCP over
//  stdio and exposes a small set of tools that fetch a CoderPad account's pads and
//  questions straight from the REST API, so an MCP-aware assistant can answer questions
//  about your interviews without the macOS app being involved.
//
//  This file is the thin executable: it loads the account configuration, makes the REST
//  calls, and wires up the stdio server. The network-free logic (account resolution,
//  argument coercion, tool schemas, and the pad code/count/aggregate transforms) lives
//  in the CoderPadMCPCore library so it can be unit-tested (#522).
//
//  The server can act as several accounts (#521), mirroring the in-app server, so every
//  account-scoped tool takes an optional `account` argument and `list_accounts` lists
//  them. Accounts come from a JSON config file (CODERPAD_MCP_CONFIG, default
//  ~/.config/coderpad-mcp/config.json):
//    { "accounts": [ { "name": "Acme", "api_key": "…", "base_url": "…",
//                      "screen_api_key": "…", "screen_region": "eu", "default": true } ],
//      "allow_writes": false }
//  With no config file the legacy single-account environment variables are used instead:
//    CODERPAD_API_KEY (required), CODERPAD_BASE_URL, CODERPAD_SCREEN_API_KEY,
//    CODERPAD_SCREEN_REGION, CODERPAD_MCP_ALLOW_WRITES.
//
//  Read tools are always available. Write tools (create/edit) are OFF unless writes are
//  opted in (#502). There is no delete tool: deletion stays a human action in the app.
//

import CoderPadMCPCore
import Foundation
import MCP

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: - Configuration

private let environment = ProcessInfo.processInfo.environment
private let screenAPIPrefix = "/assessment/api/v1.1"

private let accountSet: MCPAccountSet = {
    do {
        let config = try loadConfigObject(environment: environment)
        return try makeAccountSet(config: config, environment: environment)
    } catch {
        let message = switch error {
        case MCPConfigError.noAccounts:
            "coderpad-mcp: no accounts configured. Set CODERPAD_API_KEY, or point "
                + "CODERPAD_MCP_CONFIG at a config file with an \"accounts\" array.\n"

        case let MCPConfigError.missingAPIKey(account):
            "coderpad-mcp: account \"\(account)\" is missing its \"api_key\".\n"

        case let MCPConfigError.duplicateName(name):
            "coderpad-mcp: two accounts share the name \"\(name)\"; names must be unique.\n"

        case let MCPConfigError.multipleDefaultAccounts(names):
            "coderpad-mcp: multiple accounts are marked as default ("
                + names.joined(separator: ", ")
                + "); mark only one account as the default.\n"

        case MCPConfigError.noDefaultAccount:
            "coderpad-mcp: a config with multiple accounts must mark one as the default "
                + "(\"default\": true); relying on array order could silently switch organizations.\n"

        case let MCPConfigError.invalidScreenRegion(account, region):
            "coderpad-mcp: account \"\(account)\" has unsupported screen_region \"\(region)\"; "
                + "use \"us\" or \"eu\".\n"

        case let MCPConfigError.invalidBaseURL(account, baseURL):
            "coderpad-mcp: account \"\(account)\" has unsupported base_url \"\(baseURL)\"; "
                + "use an http or https URL with a host.\n"

        default:
            "coderpad-mcp: could not load the account configuration: \(error.localizedDescription)\n"
        }
        FileHandle.standardError.write(Data(message.utf8))
        exit(1)
    }
}()

// MARK: - CoderPad REST

/// Performs an authenticated GET against an account and returns the status and raw body.
private func apiGet(_ path: String, account: MCPAccount, query: [URLQueryItem] = []) async -> APIResponse {
    guard var comps = URLComponents(
        url: account.baseURL.appending(path: path), resolvingAgainstBaseURL: false
    ) else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }

    let items = query.filter { ($0.value ?? "").isEmpty == false }
    if !items.isEmpty { comps.queryItems = items }
    guard let url = comps.url else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }

    var request = URLRequest(url: url)
    request.setValue("Bearer \(account.apiKey)", forHTTPHeaderField: "Authorization")
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

private func errorResult(_ message: String) -> CallTool.Result {
    CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
}

/// Performs an authenticated write (POST/PUT) against an account with a JSON body.
private func apiSend(_ method: String, _ path: String, account: MCPAccount, body: [String: Any]) async -> APIResponse {
    guard let url = URLComponents(
        url: account.baseURL.appending(path: path), resolvingAgainstBaseURL: false
    )?.url else {
        return APIResponse(status: 0, body: "Could not build a URL for \(path).")
    }
    guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
        return APIResponse(status: 0, body: "Could not encode the request body.")
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = payload
    request.setValue("Bearer \(account.apiKey)", forHTTPHeaderField: "Authorization")
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

/// An authenticated GET against the CoderPad Screen API for an account, which uses an
/// `API-Key` header (not Bearer) and its own host + version prefix.
private func screenGet(_ path: String, account: MCPAccount, query: [URLQueryItem] = []) async -> APIResponse {
    guard let key = account.screenAPIKey else {
        return APIResponse(
            status: 0,
            body: "Screen is not configured for account \"\(account.name)\"."
        )
    }
    guard var comps = URLComponents(
        url: account.screenBaseURL.appending(path: screenAPIPrefix + path), resolvingAgainstBaseURL: false
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
            text: "Writes are disabled. Enable them with \"allow_writes\": true in the config "
                + "(or CODERPAD_MCP_ALLOW_WRITES=1) to use the create/edit tools.",
            annotations: nil, _meta: nil
        )],
        isError: true
    )
}

private func unknownAccount(_ requested: String?) -> CallTool.Result {
    let names = accountSet.accounts.map(\.name).joined(separator: ", ")
    return CallTool.Result(
        content: [.text(
            text: "No account matches \"\(requested ?? "")\". Available accounts: \(names). "
                + "Use list_accounts to see them.",
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

/// The tools to advertise, given the configured accounts' Screen / writes settings.
///
/// Both flags are fixed for the process lifetime, so the catalog is built once and reused
/// rather than regenerating every descriptor on each `tools/list` request (#2122).
private let advertisedTools: [Tool] = availableTools(
    screenEnabled: accountSet.anyScreenEnabled,
    writesEnabled: accountSet.allowWrites
)

// MARK: - Server

/// The CoderPad provider for MCPKit's `MCPServer`: it advertises the CoderPad
/// catalogue, prompts and resources, and runs the tool dispatch + resource reads against
/// the configured accounts. The generic server wiring (handler registration, the
/// PromptError mapping, stdio) is the shared `MCPServer`; only this CoderPad-specific
/// behaviour lives here, identical to the in-app server's provider.
struct CoderPadProvider: MCPToolProvider {
    func tools() async -> [Tool] {
        advertisedTools
    }

    func callTool(_ name: String, arguments: [String: Value]?) async -> CallTool.Result {
        // list_accounts is a directory-level query - it isn't scoped to one account.
        if name == "list_accounts" {
            return jsonResult(["accounts": accountSet.directory()])
        }

        // Resolve the target account up front so every tool gives the same clear error.
        let requestedAccount = stringArgument(arguments, "account")
        guard let account = accountSet.resolve(requestedAccount) else {
            return unknownAccount(requestedAccount)
        }

        // Write tools are gated on the opt-in, regardless of which account is targeted.
        if writeToolNames.contains(name), !accountSet.allowWrites {
            return writesDisabled()
        }

        return await dispatch(name: name, arguments: arguments, account: account)
    }

    func prompts() async -> [Prompt] {
        interviewPrompts
    }

    func getPrompt(_ name: String, arguments: [String: String]?) async throws -> GetPrompt.Result {
        try renderPrompt(name: name, arguments: arguments)
    }

    func resources() async -> [Resource] {
        staticResources(for: accountSet)
    }

    func resourceTemplates() async -> [Resource.Template] {
        // Qualified: the unqualified name resolves to this method, not the core helper.
        CoderPadMCPCore.resourceTemplates(for: accountSet)
    }

    func readResource(_ uri: String) async throws -> ReadResource.Result {
        guard let request = parseResourceURI(uri) else {
            throw MCPError.invalidParams("Unknown resource URI: \(uri)")
        }

        let account: MCPAccount = switch resolveResourceAccount(request, accountSet: accountSet) {
        case let .account(account):
            account

        case .requiresAccount:
            throw MCPError.invalidParams(
                "Resource URI must include an account in multi-account configs: "
                    + "coderpad://account/{account}/..."
            )

        case let .unknownAccount(name):
            throw MCPError.invalidParams("No account matches resource selector \"\(name)\".")
        }
        return try await coderpad_mcp.readResource(request.unqualified, uri: uri, account: account)
    }
}

let server = MCPServer(name: "PadBuddy", version: "0.1.0", provider: CoderPadProvider())

// MARK: - Tool dispatch

/// The names of the write tools, gated on the writes opt-in. Kept as one set so the
/// `tools/list` filter and the call gate can't drift apart.
let writeToolNames: Set<String> = ["create_pad", "update_pad", "create_question", "update_question"]

/// Runs one account-scoped tool against the resolved account.
private func dispatch(name: String, arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    switch name {
    case "whoami":
        return await whoami(account: account)

    case "list_pads":
        return await listPads(arguments: arguments, account: account)

    case "get_pad":
        guard let pad = stringArgument(arguments, "pad"), !pad.isEmpty else { return missingArgument("pad") }

        return await toolResult(apiGet("/api/pads/\(pad)", account: account))

    case "get_pad_code":
        guard let pad = stringArgument(arguments, "pad"), !pad.isEmpty else { return missingArgument("pad") }

        return await getPadCode(id: pad, maxFileChars: intArgument(arguments, "max_file_chars"), account: account)

    case "count_pads":
        return await countPads(arguments: arguments, account: account)

    case "aggregate_pads":
        guard let groupBy = stringArgument(arguments, "group_by"), !groupBy.isEmpty else {
            return missingArgument("group_by")
        }

        return await aggregatePadsTool(groupBy: groupBy, arguments: arguments, account: account)

    case "list_pads_compact":
        return await listPadsCompact(arguments: arguments, account: account)

    case "list_questions":
        return await listQuestions(arguments: arguments, account: account)

    case "get_question":
        guard let question = intArgument(arguments, "question") else { return missingArgument("question (integer)") }

        return await toolResult(apiGet("/api/questions/\(question)", account: account))

    case "count_questions":
        return await countQuestions(arguments: arguments, account: account)

    case "aggregate_questions":
        guard let groupBy = stringArgument(arguments, "group_by"), !groupBy.isEmpty else {
            return missingArgument("group_by")
        }

        return await aggregateQuestionsTool(groupBy: groupBy, arguments: arguments, account: account)

    case "list_questions_compact":
        return await listQuestionsCompact(arguments: arguments, account: account)

    case "get_quota":
        return await toolResult(apiGet("/api/quota", account: account))

    case "get_organization":
        return await toolResult(apiGet("/api/organization", account: account))

    default:
        return await dispatchScreenOrWrite(name: name, arguments: arguments, account: account)
    }
}

/// The Screen and write tools, split out so `dispatch` stays within the
/// cyclomatic-complexity budget.
private func dispatchScreenOrWrite(
    name: String, arguments: [String: Value]?, account: MCPAccount
) async -> CallTool.Result {
    switch name {
    case "screen_list_campaigns":
        return await toolResult(screenGet("/campaigns", account: account))

    case "screen_list_tests":
        if let error = screenPaginationValidationError(
            start: intArgument(arguments, "start"),
            limit: intArgument(arguments, "limit")
        ) {
            return errorResult(error)
        }

        return await toolResult(screenGet("/tests", account: account, query: screenTestQuery(arguments)))

    case "screen_get_test":
        guard let test = intArgument(arguments, "test") else { return missingArgument("test (integer)") }

        return await toolResult(screenGet("/tests/\(test)", account: account))

    case "create_pad":
        return await createPad(arguments: arguments, account: account)

    case "update_pad":
        guard let pad = stringArgument(arguments, "pad"), !pad.isEmpty else { return missingArgument("pad") }

        return await updatePad(id: pad, arguments: arguments, account: account)

    case "create_question":
        guard let title = optionalString(arguments, "title") else { return missingArgument("title") }

        return await createQuestion(title: title, arguments: arguments, account: account)

    case "update_question":
        guard let question = intArgument(arguments, "question") else { return missingArgument("question (integer)") }

        return await updateQuestion(id: question, arguments: arguments, account: account)

    default:
        return CallTool.Result(
            content: [.text(text: "Unknown tool: \(name)", annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

private func screenTestQuery(_ arguments: [String: Value]?) -> [URLQueryItem] {
    var query: [URLQueryItem] = []
    if let campaign = intArgument(arguments, "campaignId") {
        query.append(URLQueryItem(name: "campaignId", value: String(campaign)))
    }
    if let email = stringArgument(arguments, "candidateEmail") {
        query.append(URLQueryItem(name: "candidateEmail", value: email))
    }
    if let start = intArgument(arguments, "start") {
        query.append(URLQueryItem(name: "start", value: String(start)))
    }
    if let limit = intArgument(arguments, "limit") {
        query.append(URLQueryItem(name: "limit", value: String(limit)))
    }
    return query
}

// MARK: - whoami (#518)

/// Reports which account/org this server acts as, without the API key: the account
/// name, the org name (fetched from `/api/organization`), the base URL, and whether
/// Screen and writes are enabled.
private func whoami(account: MCPAccount) async -> CallTool.Result {
    var info: [String: Any] = [
        "account": account.name,
        "base_url": account.baseURL.absoluteString,
        "screen_configured": account.screenEnabled,
        "writes_enabled": accountSet.allowWrites
    ]

    let org = await apiGet("/api/organization", account: account)
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
private func padCodeJSON(id: String, maxFileChars: Int?, account: MCPAccount) async throws -> String {
    if let error = maxFileCharsValidationError(maxFileChars) {
        throw MCPError.invalidParams(error)
    }

    let padResponse = await apiGet("/api/pads/\(id)", account: account)
    guard padResponse.ok else {
        throw MCPError.internalError("HTTP \(padResponse.status)\n\(padResponse.body)")
    }
    guard let pad = jsonObject(padResponse.body) else {
        throw MCPError.internalError("Could not parse the pad response as JSON.")
    }

    // Fetched concurrently: a pad with several environments used to pay one full
    // round-trip after another, so latency added up linearly on the hot path behind
    // get_pad_code and the pad-code resource (#2260). Results are collected by index
    // and then read back in order, so the output — and which ids are reported as
    // failed — is identical to the sequential version.
    let ids = environmentIDs(in: pad)
    // The response bodies cross the task boundary, not the parsed objects:
    // `[String: Any]` is not Sendable, so parsing happens on the collecting side.
    var bodies: [Int: String] = [:]
    await withTaskGroup(of: (offset: Int, body: String?).self) { group in
        for (offset, environmentID) in ids.enumerated() {
            group.addTask {
                let response = await apiGet("/api/pad_environments/\(environmentID)", account: account)
                return (offset, response.ok ? response.body : nil)
            }
        }
        for await result in group {
            bodies[result.offset] = result.body
        }
    }

    var environments: [PadCodeEnvironment] = []
    var failedEnvironmentIDs: [Int] = []
    for (offset, environmentID) in ids.enumerated() {
        guard let body = bodies[offset], let object = jsonObject(body) else {
            failedEnvironmentIDs.append(environmentID)
            continue
        }

        environments.append(PadCodeEnvironment(id: environmentID, object: object))
    }

    let payload = padCodePayload(
        id: id, pad: pad, environments: environments,
        failedEnvironmentIDs: failedEnvironmentIDs, maxFileChars: maxFileChars
    )
    guard let data = try? JSONSerialization.data(
        withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
    ) else {
        throw MCPError.internalError("Could not encode the pad code.")
    }

    return String(decoding: data, as: UTF8.self)
}

private func getPadCode(id: String, maxFileChars: Int?, account: MCPAccount) async -> CallTool.Result {
    do {
        let json = try await padCodeJSON(id: id, maxFileChars: maxFileChars, account: account)
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
private func readResource(_ request: ResourceRequest, uri: String, account: MCPAccount) async throws -> ReadResource.Result {
    func jsonResource(_ path: String) async throws -> ReadResource.Result {
        let response = await apiGet(path, account: account)
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
        let json = try await padCodeJSON(id: id, maxFileChars: nil, account: account)
        return ReadResource.Result(contents: [.text(json, uri: uri, mimeType: "application/json")])

    case .accountQuota, .accountOrganization, .accountPad, .accountPadCode, .accountQuestion:
        // The caller resolves the account and passes `request.unqualified`, so these
        // only arrive if a new call site forgets to; strip the qualifier and recurse.
        return try await readResource(request.unqualified, uri: uri, account: account)
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

/// The accumulated result of paging the whole pad list internally. Only the totals are
/// kept: the pages themselves are handed to the caller's tally as they arrive (#2121).
private struct PadPageScan {
    var scanned = 0
    var totalReported: Int?
    var pagesFetched = 0
    var truncated = false
    var error: APIResponse?
    /// Set when a 2xx page decoded to JSON but lacked the expected records array —
    /// an API schema change or 200-wrapped error page, which must be surfaced rather
    /// than silently counted as zero rows (#1024).
    var invalidShape: String?
}

/// Pages `/api/pads/` from the first page following `next_page`, handing each page to
/// `consume`, so the count/aggregate tools can tally in-process and return a small answer
/// instead of streaming thousands of records through the model. Pages are tallied and
/// then dropped rather than retained, so a huge org does not sit in memory purely to be
/// filtered once at the end (#2121).
private func fetchAllPads(account: MCPAccount, consume: ([[String: Any]]) -> Void) async -> PadPageScan {
    var scan = PadPageScan()
    var page: String?
    while scan.pagesFetched < maxPadPagesToFetch {
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: page)) }
        let response = await apiGet("/api/pads/", account: account, query: query)
        guard response.ok, let object = jsonObject(response.body) else {
            scan.error = response
            return scan
        }
        guard let pads = object["pads"] as? [[String: Any]] else {
            scan.invalidShape = invalidListResponseMessage("/api/pads/", expecting: "pads", body: response.body)
            return scan
        }

        if scan.totalReported == nil { scan.totalReported = object["total"] as? Int }
        consume(pads)
        scan.scanned += pads.count
        scan.pagesFetched += 1
        guard let next = nextPageToken(object["next_page"]) else { return scan }

        page = next
    }

    scan.truncated = true
    return scan
}

private func countPads(arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    let owner = stringArgument(arguments, "owner")
    let state = stringArgument(arguments, "state")
    let language = stringArgument(arguments, "language")
    let after = stringArgument(arguments, "created_after")
    let before = stringArgument(arguments, "created_before")
    if let error = dateBoundValidationError(after: after, before: before) { return errorResult(error) }

    // Built once for the whole list rather than re-normalizing the filter
    // values for every row (#2453).
    let matcher = PadMatcher(owner: owner, state: state, language: language)
    var matched = 0
    let scan = await fetchAllPads(account: account) { pads in
        for pad in pads where matcher.matches(pad) && withinDateRange(pad, after: after, before: before) {
            matched += 1
        }
    }
    if let error = scan.error { return toolResult(error) }
    if let message = scan.invalidShape { return errorResult(message) }

    var result: [String: Any] = [
        "matched": matched,
        "scanned": scan.scanned,
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

private func aggregatePadsTool(groupBy: String, arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
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
    if let error = dateBoundValidationError(after: after, before: before) { return errorResult(error) }

    // Built once for the whole list rather than re-normalizing the filter
    // values for every row (#2453).
    let matcher = PadMatcher(owner: owner, state: state, language: language)
    var matched = 0
    var counts: [String: Int] = [:]
    let scan = await fetchAllPads(account: account) { pads in
        let page = pads.filter {
            matcher.matches($0)
                && withinDateRange($0, after: after, before: before)
        }
        matched += page.count
        accumulateCounts(&counts, pads: page, field: field)
    }
    if let error = scan.error { return toolResult(error) }
    if let message = scan.invalidShape { return errorResult(message) }

    let capped = topGroups(counts, limit: maxAggregateGroups)
    let groups: [[String: Any]] = capped.map { ["value": $0.value, "count": $0.count] }

    var result: [String: Any] = [
        "group_by": field,
        "matched": matched,
        "scanned": scan.scanned,
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

private func listPads(arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    if let error = pageValidationError(intArgument(arguments, "page")) { return errorResult(error) }

    return await toolResult(apiGet("/api/pads/", account: account, query: pagingQuery(arguments)))
}

private func listPadsCompact(arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    if let error = pageValidationError(intArgument(arguments, "page")) { return errorResult(error) }

    let response = await apiGet("/api/pads/", account: account, query: pagingQuery(arguments))
    guard response.ok, let object = jsonObject(response.body) else { return toolResult(response) }
    guard let pads = object["pads"] as? [[String: Any]] else {
        return errorResult(invalidListResponseMessage("/api/pads/", expecting: "pads", body: response.body))
    }

    let compact = compactPads(pads)

    var result: [String: Any] = ["pads": compact, "count": compact.count]
    if let next = object["next_page"], !(next is NSNull) { result["next_page"] = next }
    if let total = object["total"], !(total is NSNull) { result["total"] = total }

    return jsonResult(result)
}

// MARK: - count_questions / aggregate_questions / list_questions_compact (#500)

/// The accumulated result of paging the whole question bank internally. See
/// `PadPageScan`: only the totals are kept (#2121).
private struct QuestionPageScan {
    var scanned = 0
    var totalReported: Int?
    var pagesFetched = 0
    var truncated = false
    var error: APIResponse?
    /// See `PadPageScan.invalidShape` (#1024).
    var invalidShape: String?
}

/// Pages `/api/questions/` from the first page following `next_page`, handing each page
/// to `consume`, so the count/aggregate tools can tally in-process and return a small
/// answer instead of streaming thousands of records through the model. Pages are tallied
/// and then dropped rather than retained (#2121).
private func fetchAllQuestions(account: MCPAccount, consume: ([[String: Any]]) -> Void) async -> QuestionPageScan {
    var scan = QuestionPageScan()
    var page: String?
    while scan.pagesFetched < maxPadPagesToFetch {
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: page)) }
        let response = await apiGet("/api/questions/", account: account, query: query)
        guard response.ok, let object = jsonObject(response.body) else {
            scan.error = response
            return scan
        }
        guard let questions = object["questions"] as? [[String: Any]] else {
            scan.invalidShape = invalidListResponseMessage(
                "/api/questions/", expecting: "questions", body: response.body
            )
            return scan
        }

        if scan.totalReported == nil { scan.totalReported = object["total"] as? Int }
        consume(questions)
        scan.scanned += questions.count
        scan.pagesFetched += 1
        guard let next = nextPageToken(object["next_page"]) else { return scan }

        page = next
    }

    scan.truncated = true
    return scan
}

private func countQuestions(arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    let owner = stringArgument(arguments, "owner")
    let author = stringArgument(arguments, "author")
    let language = stringArgument(arguments, "language")
    let type = stringArgument(arguments, "type")
    let after = stringArgument(arguments, "created_after")
    let before = stringArgument(arguments, "created_before")
    if let error = dateBoundValidationError(after: after, before: before) { return errorResult(error) }

    // Built once for the whole list rather than re-normalizing the filter
    // values for every row (#2452).
    let matcher = QuestionMatcher(owner: owner, author: author, language: language, type: type)
    var matched = 0
    let scan = await fetchAllQuestions(account: account) { questions in
        for question in questions
            where matcher.matches(question) && withinDateRange(question, after: after, before: before) {
            matched += 1
        }
    }
    if let error = scan.error { return toolResult(error) }
    if let message = scan.invalidShape { return errorResult(message) }

    var result: [String: Any] = [
        "matched": matched,
        "scanned": scan.scanned,
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

private func aggregateQuestionsTool(groupBy: String, arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
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
    if let error = dateBoundValidationError(after: after, before: before) { return errorResult(error) }

    // Built once for the whole list rather than re-normalizing the filter
    // values for every row (#2452).
    let matcher = QuestionMatcher(owner: owner, author: author, language: language, type: type)
    var matched = 0
    var counts: [String: Int] = [:]
    let scan = await fetchAllQuestions(account: account) { questions in
        let page = questions.filter {
            matcher.matches($0)
                && withinDateRange($0, after: after, before: before)
        }
        matched += page.count
        accumulateCounts(&counts, pads: page, field: field)
    }
    if let error = scan.error { return toolResult(error) }
    if let message = scan.invalidShape { return errorResult(message) }

    let capped = topGroups(counts, limit: maxAggregateGroups)
    let groups: [[String: Any]] = capped.map { ["value": $0.value, "count": $0.count] }

    var result: [String: Any] = [
        "group_by": field,
        "matched": matched,
        "scanned": scan.scanned,
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

private func listQuestions(arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    if let error = pageValidationError(intArgument(arguments, "page")) { return errorResult(error) }

    return await toolResult(apiGet("/api/questions/", account: account, query: pagingQuery(arguments)))
}

private func listQuestionsCompact(arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    if let error = pageValidationError(intArgument(arguments, "page")) { return errorResult(error) }

    let response = await apiGet("/api/questions/", account: account, query: pagingQuery(arguments))
    guard response.ok, let object = jsonObject(response.body) else { return toolResult(response) }
    guard let questions = object["questions"] as? [[String: Any]] else {
        return errorResult(invalidListResponseMessage("/api/questions/", expecting: "questions", body: response.body))
    }

    let compact = compactQuestions(questions)

    var result: [String: Any] = ["questions": compact, "count": compact.count]
    if let next = object["next_page"], !(next is NSNull) { result["next_page"] = next }
    if let total = object["total"], !(total is NSNull) { result["total"] = total }

    return jsonResult(result)
}

// MARK: - Write tools (#502, gated behind the writes opt-in)

private func presentString(_ arguments: [String: Value]?, _ name: String) -> String? {
    guard let value = arguments?[name] else { return nil }

    switch value {
    case let .string(string):
        return string
    case let .int(int):
        return String(int)
    case let .double(double):
        return String(double)
    default:
        return nil
    }
}

private func createPad(arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    if let error = padSeedValidationError(
        questionID: intArgument(arguments, "question_id"),
        contents: optionalString(arguments, "contents")
    ) {
        return errorResult(error)
    }

    var body: [String: Any] = [:]
    if let title = optionalString(arguments, "title") { body["title"] = title }
    if let language = optionalString(arguments, "language") { body["language"] = language }
    if let owner = optionalString(arguments, "owner_email") { body["owner_email"] = owner }
    if let contents = optionalString(arguments, "contents") { body["contents"] = contents }
    if let notes = optionalString(arguments, "notes") { body["notes"] = notes }
    if let questionID = intArgument(arguments, "question_id") { body["question_id"] = questionID }
    if let teamID = optionalString(arguments, "team_id") { body["team_id"] = teamID }

    return await toolResult(apiSend("POST", "/api/pads/", account: account, body: body))
}

private func updatePad(id: String, arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    var body: [String: Any] = [:]
    if let title = presentString(arguments, "title") { body["title"] = title }
    if let notes = presentString(arguments, "notes") { body["notes"] = notes }
    if let owner = presentString(arguments, "owner_email") { body["owner_email"] = owner }
    if let language = presentString(arguments, "language") { body["language"] = language }
    guard !body.isEmpty else {
        return missingArgument("at least one of title / notes / owner_email / language")
    }

    return await toolResult(apiSend("PUT", "/api/pads/\(id)", account: account, body: body))
}

private func createQuestion(title: String, arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    var question: [String: Any] = ["title": title]
    if let language = optionalString(arguments, "language") { question["language"] = language }
    var body: [String: Any] = ["question": question]
    if let description = optionalString(arguments, "description") { body["description"] = description }
    if let solution = optionalString(arguments, "solution") { body["solution"] = solution }
    if let contents = optionalString(arguments, "contents") { body["contents"] = contents }

    return await toolResult(apiSend("POST", "/api/questions/", account: account, body: body))
}

private func updateQuestion(id: Int, arguments: [String: Value]?, account: MCPAccount) async -> CallTool.Result {
    var question: [String: Any] = [:]
    if let title = presentString(arguments, "title") { question["title"] = title }
    if let language = presentString(arguments, "language") { question["language"] = language }
    var body: [String: Any] = [:]
    if !question.isEmpty { body["question"] = question }
    if let description = presentString(arguments, "description") { body["description"] = description }
    if let solution = presentString(arguments, "solution") { body["solution"] = solution }
    if let contents = presentString(arguments, "contents") { body["contents"] = contents }
    guard !body.isEmpty else {
        return missingArgument("at least one of title / language / description / solution / contents")
    }

    return await toolResult(apiSend("PUT", "/api/questions/\(id)", account: account, body: body))
}

// MARK: - Run

try await server.run(transport: StdioTransport())
