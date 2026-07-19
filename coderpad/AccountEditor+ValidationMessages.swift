//
//  AccountEditor+ValidationMessages.swift
//  coderpad
//
//  Split from AccountEditor+Logic.swift to keep it within the lint length limit:
//  the user-facing validation failure message helpers moved here.
//

import Foundation

extension AccountEditor {
    func friendlyValidationMessage(for error: any Error) -> String {
        if let api = error as? CoderPadError {
            if api.isUnauthorized {
                return String(localized: """
                CoderPad rejected this key. Double-check that it's the right one and hasn't been revoked.
                """)
            }
            switch api {
            case .missingAPIKey:
                return String(localized: "Paste your CoderPad API key above.")

            case let .http(code, body):
                return friendlyHTTPValidationMessage(status: code, body: body)

            case .decode:
                return String(localized: """
                CoderPad returned something unexpected. Try again, and if it keeps happening, \
                regenerate the key.
                """)

            case .network:
                return api.errorDescription ?? String(localized: """
                Couldn't reach CoderPad. Check your internet connection and try again.
                """)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return String(localized: "Couldn't reach CoderPad. Check your internet connection and try again.")
        }
        return String(localized: "Couldn't validate this key. Try again.")
    }

    private func friendlyHTTPValidationMessage(status code: Int, body: String) -> String {
        switch code {
        case 404:
            return String(localized: """
            CoderPad couldn't find the API endpoint at this Server URL. \
            Hosted accounts should use https://app.coderpad.io.
            """)

        case 429:
            return String(localized: "CoderPad is rate-limiting validation right now. Try again in a moment.")

        case 500 ... 599:
            return String(localized: "CoderPad had a server error while validating this key. Try again shortly.")

        default:
            if let apiMessage = validationAPIMessage(from: body) {
                return String(localized: "CoderPad couldn't validate this key: \(apiMessage)")
            }
            return String(localized: "CoderPad couldn't validate this key (HTTP \(code)).")
        }
    }

    private func validationAPIMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        for key in ["message", "error_description", "error"] {
            guard let value = object[key] as? String else { continue }

            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.lowercased() != "not found" {
                return trimmed
            }
        }
        return nil
    }
}
