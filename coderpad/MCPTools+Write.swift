//
//  MCPTools+Write.swift
//  coderpad
//
//  The optional write tools for the in-app MCP server (#502). These are off by default
//  and only advertised / runnable when the user turns on "Allow the MCP server to make
//  changes" (see `MCPAccountDirectory.allowWrites`). Each tool wraps the same encode-only
//  request body the app itself sends (`PadCreate`, `PadUpdate`, `QuestionCreate`,
//  `QuestionUpdate`), so the MCP path inherits the API's quirks (the `execution_enabled`
//  string form, the nested `question` object) for free and can't drift from the app.
//
//  Deletion is deliberately NOT exposed: removing interview content stays a human action
//  in the app. The write tools are marked with MCP `readOnlyHint: false` annotations so
//  clients can prompt before running them.
//

import Foundation

nonisolated extension MCPTools {
    /// Routes a write tool to its CoderPad endpoint. Reached only after `run` has confirmed
    /// the opt-in and resolved the account, so the gating lives in one place.
    static func dispatchWrite(
        name: String, arguments: [String: Any], credentials: MCPCredentials
    ) async -> Outcome {
        let key = credentials.apiKey
        let base = credentials.baseURL
        let accountID = credentials.id

        switch name {
        case "create_pad":
            let outcome = await createPad(arguments: arguments, key: key, base: base)
            return invalidateCache(kind: "pads", accountID: accountID, after: outcome)

        case "update_pad":
            let outcome = await updatePad(arguments: arguments, key: key, base: base)
            return invalidateCache(kind: "pads", accountID: accountID, after: outcome)

        case "create_question":
            let outcome = await createQuestion(arguments: arguments, key: key, base: base)
            return invalidateCache(kind: "questions", accountID: accountID, after: outcome)

        case "update_question":
            let outcome = await updateQuestion(arguments: arguments, key: key, base: base)
            return invalidateCache(kind: "questions", accountID: accountID, after: outcome)

        default:
            return Outcome(text: "Unknown tool: \(name)", isError: true)
        }
    }

    static func invalidateCache(kind: String, accountID: String, after outcome: Outcome) -> Outcome {
        guard !outcome.isError, let account = UUID(uuidString: accountID) else { return outcome }

        CacheDisk.delete(kind: kind, account: account)
        return outcome
    }

    // MARK: - Implementations

    private static func createPad(arguments: [String: Any], key: String, base: URL) async -> Outcome {
        if let error = padSeedValidationError(
            questionID: int(arguments, "question_id"),
            contents: string(arguments, "contents")
        ) {
            return Outcome(text: error, isError: true)
        }

        let body = padCreateBody(from: arguments)
        return await send("POST", "/api/pads/", key: key, base: base, body: body)
    }

    /// Builds the create-pad request body from the tool arguments. Split out from
    /// `createPad` so each function stays small enough to type-check within the
    /// compiler's per-body limit (warnings-as-errors turns an overrun into a build failure).
    private static func padCreateBody(from arguments: [String: Any]) -> PadCreate {
        var body = PadCreate()
        body.title = string(arguments, "title")
        body.language = string(arguments, "language")
        body.questionID = int(arguments, "question_id")
        // `contents` and `team_id` are part of the shared catalog (#521); the API treats
        // contents and question_id as mutually exclusive seeds.
        body.contents = string(arguments, "contents")
        body.ownerEmail = string(arguments, "owner_email")
        body.notes = string(arguments, "notes")
        body.teamID = string(arguments, "team_id")
        return body
    }

    private static func updatePad(arguments: [String: Any], key: String, base: URL) async -> Outcome {
        guard let pad = string(arguments, "pad") else { return missing("pad") }
        guard hasAnyUpdatePadField(arguments) else {
            return missing("at least one of title / notes / owner_email / language")
        }

        let body = padUpdateBody(id: pad, arguments: arguments)
        // The pad id travels in the URL path per the API (PUT /api/pads/:id).
        return await send("PUT", "/api/pads/\(pad)", key: key, base: base, body: body,
                          successText: "Updated pad \(pad).")
    }

    static func hasAnyUpdatePadField(_ arguments: [String: Any]) -> Bool {
        ["title", "notes", "owner_email", "language"].contains { arguments.keys.contains($0) }
    }

    static func padUpdateBody(id pad: String, arguments: [String: Any]) -> PadUpdate {
        var body = PadUpdate(id: pad)
        body.title = presentString(arguments, "title")
        body.notes = presentString(arguments, "notes")
        body.ownerEmail = presentString(arguments, "owner_email")
        body.language = presentString(arguments, "language")
        return body
    }

    private static func createQuestion(arguments: [String: Any], key: String, base: URL) async -> Outcome {
        guard let title = requiredString(arguments, "title") else { return missing("title") }

        let body = questionCreateBody(title: title, arguments: arguments)
        return await send("POST", "/api/questions/", key: key, base: base, body: body)
    }

    static func questionCreateBody(title: String, arguments: [String: Any]) -> QuestionCreate {
        var body = QuestionCreate(title: title)
        body.language = string(arguments, "language")
        body.description = string(arguments, "description")
        body.solution = string(arguments, "solution")
        body.contents = string(arguments, "contents")
        return body
    }

    private static func updateQuestion(arguments: [String: Any], key: String, base: URL) async -> Outcome {
        guard let id = int(arguments, "question") else { return missing("question") }
        guard hasAnyUpdateQuestionField(arguments) else {
            return missing("at least one of title / language / description / solution / contents")
        }

        let body = questionUpdateBody(id: id, arguments: arguments)
        return await send("PUT", "/api/questions/\(id)", key: key, base: base, body: body,
                          successText: "Updated question \(id).")
    }

    static func hasAnyUpdateQuestionField(_ arguments: [String: Any]) -> Bool {
        ["title", "language", "description", "solution", "contents"].contains { arguments.keys.contains($0) }
    }

    static func questionUpdateBody(id: Int, arguments: [String: Any]) -> QuestionUpdate {
        var body = QuestionUpdate(id: id)
        body.title = presentString(arguments, "title")
        body.language = presentString(arguments, "language")
        body.description = presentString(arguments, "description")
        body.solution = presentString(arguments, "solution")
        body.contents = presentString(arguments, "contents")
        return body
    }

    // MARK: - HTTP

    /// Encodes `body` and performs an authenticated write request, returning the API's JSON
    /// verbatim on success (or `successText` when the endpoint replies with only a status,
    /// as the PUT update endpoints do), and the HTTP status / failure reason on error.
    private static func send(
        _ method: String,
        _ path: String,
        key: String,
        base: URL,
        body: some Encodable,
        successText: String? = nil
    ) async -> Outcome {
        let data: Data
        do {
            data = try JSONEncoder().encode(body)
        } catch {
            return Outcome(text: "Could not encode the request: \(error.localizedDescription)", isError: true)
        }

        guard let url = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)?.url else {
            return Outcome(text: "Could not build a URL for \(path).", isError: true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let responseBody = String(bytes: responseData, encoding: .utf8) ?? ""
            if (200 ..< 300).contains(status) {
                let text = responseBody.isEmpty ? (successText ?? "OK") : responseBody
                return Outcome(text: text, isError: false)
            }
            return Outcome(text: "HTTP \(status)\n\(responseBody)", isError: true)
        } catch {
            return Outcome(text: "Request to \(path) failed: \(error.localizedDescription)", isError: true)
        }
    }
}
