//
//  MCPTools+Tools.swift
//  coderpad
//
//  The in-app MCP server's directory/identity/code tools, split out of MCPTools.swift
//  to keep that file within its length budget: list_accounts (#519), whoami (#518), and
//  get_pad_code (#499). The pad-code assembly itself is the pure CoderPadToolCore helpers.
//

import Foundation

nonisolated extension MCPTools {
    // MARK: - list_accounts (#519)

    /// Lists every configured account the server can act as — id, display name, resolved
    /// user email, base URL, and whether it's the current default — as JSON. API keys are
    /// deliberately never included.
    static func listAccounts(directory: MCPAccountDirectory) -> Outcome {
        let currentID = directory.current?.id
        let list: [[String: Any]] = directory.accounts.map { account in
            [
                "id": account.id,
                "name": account.accountName,
                "user_email": account.userEmail,
                "base_url": account.baseURL.absoluteString,
                "is_current": account.id == currentID
            ]
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: ["accounts": list], options: [.prettyPrinted, .sortedKeys]
        ), let text = String(bytes: data, encoding: .utf8) else {
            return Outcome(text: "Could not encode the account list.", isError: true)
        }

        return Outcome(text: text, isError: false)
    }

    // MARK: - get_pad_code (#499)

    /// Fetches a pad and each of its environments, then assembles the compact code JSON
    /// via the pure `padCodePayload` helper.
    static func getPadCode(pad id: String, maxFileChars: Int?, key: String, base: URL) async -> Outcome {
        if let error = maxFileCharsValidationError(maxFileChars) {
            return Outcome(text: error, isError: true)
        }

        let padResponse = await get("/api/pads/\(id)", key: key, base: base)
        guard !padResponse.isError else { return padResponse }
        guard let pad = jsonObject(padResponse) else {
            return Outcome(text: "Could not parse the pad response as JSON.", isError: true)
        }

        var environments: [CoderPadToolCore.PadCodeEnvironment] = []
        var failedEnvironmentIDs: [Int] = []
        for environmentID in environmentIDs(in: pad) {
            let response = await get("/api/pad_environments/\(environmentID)", key: key, base: base)
            guard !response.isError, let object = jsonObject(response) else {
                failedEnvironmentIDs.append(environmentID)
                continue
            }

            environments.append(CoderPadToolCore.PadCodeEnvironment(id: environmentID, object: object))
        }

        let payload = padCodePayload(
            id: id, pad: pad, environments: environments,
            failedEnvironmentIDs: failedEnvironmentIDs, maxFileChars: maxFileChars
        )
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]
        ) else {
            return Outcome(text: "Could not encode the pad code.", isError: true)
        }

        return Outcome(text: String(bytes: data, encoding: .utf8) ?? "", isError: false)
    }

    /// Parses a JSON object body into a dictionary, or nil if it isn't an object.
    static func jsonObject(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else { return nil }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The parsed JSON body of a response, using the bytes it already carries rather
    /// than re-encoding `text` back to `Data` (#2241). Falls back to the string for an
    /// outcome that has no bytes (an error, or one synthesized in a test).
    static func jsonObject(_ outcome: Outcome) -> [String: Any]? {
        guard let data = outcome.data else { return jsonObject(outcome.text) }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - whoami (#518)

    /// Reports the acting account's identity as JSON: its display name and resolved user
    /// email (known locally, since the CoderPad API doesn't expose the key's owner), the
    /// server base URL, and the organization name (fetched from `/api/organization`). The
    /// API key is deliberately never included. If the org fetch fails, the local fields
    /// are still returned with a note, so `whoami` stays useful offline.
    static func whoami(credentials: MCPCredentials) async -> Outcome {
        var info: [String: Any] = [
            "account_name": credentials.accountName,
            "user_email": credentials.userEmail,
            "base_url": credentials.baseURL.absoluteString
        ]

        let org = await get("/api/organization", key: credentials.apiKey, base: credentials.baseURL)
        if !org.isError,
           let data = org.text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["organization_name"] as? String {
            info["organization_name"] = name
        } else {
            info["organization_note"] = "Could not fetch the organization name from the API."
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: info, options: [.prettyPrinted, .sortedKeys]
        ), let text = String(bytes: data, encoding: .utf8) else {
            return Outcome(text: "Could not encode the account info.", isError: true)
        }

        return Outcome(text: text, isError: false)
    }
}
