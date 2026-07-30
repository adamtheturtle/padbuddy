//
//  MCPTools+Screen.swift
//  coderpad
//
//  The read-only CoderPad Screen tools for the in-app MCP server (#499, #314), mirroring
//  the standalone server's screen_list_campaigns / screen_list_tests / screen_get_test.
//  Screen is a separate product on a different host (www.codingame.com, or .eu for EU
//  customers) under /assessment/api/v1.1, authenticated with an `API-Key` header rather
//  than a bearer token. The tools are advertised only when some account has a Screen key,
//  and each call resolves the targeted account's own Screen credentials.
//

import Foundation

nonisolated extension MCPTools {
    /// The Screen tool names (#499), from the shared catalog. Read-only, so they are not
    /// gated on the write opt-in; they are advertised only when an account carries a Screen
    /// key. The descriptors themselves live in CoderPadToolCore (#521).
    static let screenToolNames = coderPadScreenToolNames

    /// Routes a Screen tool to its endpoint against the resolved account's Screen
    /// credentials, erroring clearly when that account has no Screen key configured.
    static func dispatchScreen(
        name: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        guard let key = credentials.secondaryApiKey, let base = credentials.secondaryBaseURL else {
            return Outcome(
                text: "Screen is not configured for the \"\(credentials.accountName)\" account. "
                    + "Add a Screen API key to that account in PadBuddy to use the screen_* tools.",
                isError: true
            )
        }

        switch name {
        case "screen_list_campaigns":
            return await screenGet("/campaigns", key: key, base: base, account: credentials.accountName)

        case "screen_list_tests":
            if let error = screenPaginationValidationError(
                start: int(arguments, "start"),
                limit: int(arguments, "limit")
            ) {
                return Outcome(text: error, isError: true)
            }

            return await screenGet("/tests", key: key, base: base, query: screenTestsQuery(arguments),
                                   account: credentials.accountName)

        case "screen_get_test":
            guard let id = positiveID(int(arguments, "test")) else {
                return Outcome(text: "test must be a positive integer.", isError: true)
            }

            return await screenGet("/tests/\(id)", key: key, base: base, account: credentials.accountName)

        default:
            return Outcome(text: "Unknown tool: \(name)", isError: true)
        }
    }

    /// Builds the optional filter/pagination query for screen_list_tests.
    private static func screenTestsQuery(_ arguments: [String: Any]) -> [URLQueryItem] {
        var query: [URLQueryItem] = []
        if let campaign = int(arguments, "campaignId") {
            query.append(URLQueryItem(name: "campaignId", value: String(campaign)))
        }
        if let email = string(arguments, "candidateEmail") {
            query.append(URLQueryItem(name: "candidateEmail", value: email))
        }
        if let start = int(arguments, "start") { query.append(URLQueryItem(name: "start", value: String(start))) }
        if let limit = int(arguments, "limit") { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        return query
    }

    /// The Screen API path prefix, shared by every Screen endpoint.
    private static let screenAPIPrefix = "/assessment/api/v1.1"

    /// Performs an authenticated Screen GET (the `API-Key` header, not a bearer token) and
    /// returns the raw JSON body verbatim, or an error outcome with the HTTP status.
    /// Errors name the owning `account` (display name) and the Screen host: with
    /// several merged accounts the same tool can serve any of them, and an
    /// unattributed failure doesn't say whose Screen key or region to fix (#688).
    static func screenGet(
        _ path: String, key: String, base: URL, query: [URLQueryItem] = [], account: String? = nil
    ) async -> Outcome {
        guard var components = URLComponents(
            url: base.appending(path: screenAPIPrefix + path), resolvingAgainstBaseURL: false
        ) else {
            return Outcome(text: "Could not build a URL for \(path).", isError: true)
        }

        let items = query.filter { ($0.value ?? "").isEmpty == false }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else {
            return Outcome(text: "Could not build a URL for \(path).", isError: true)
        }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(bytes: data, encoding: .utf8) ?? ""
            if (200 ..< 300).contains(status) {
                return Outcome(text: body, isError: false)
            }
            return Outcome(
                text: sanitizedHTTPErrorMessage(
                    status: status,
                    body: body,
                    context: attribution(account, base: base)
                ),
                isError: true
            )
        } catch {
            return Outcome(
                text: "Request to \(path)\(attribution(account, base: base)) failed: \(error.localizedDescription)",
                isError: true
            )
        }
    }

    /// The " for the "Name" account's Screen server (host)" suffix on Screen errors,
    /// so a merged-mode failure identifies whose credentials and region were used.
    private static func attribution(_ account: String?, base: URL) -> String {
        let host = base.host ?? base.absoluteString
        guard let account, !account.isEmpty else { return " (Screen server \(host))" }

        return " for the \"\(account)\" account's Screen server (\(host))"
    }
}
