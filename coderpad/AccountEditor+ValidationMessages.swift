//
//  AccountEditor+ValidationMessages.swift
//  coderpad
//
//  Split from AccountEditor+Logic.swift to keep it within the lint length limit:
//  the user-facing validation failure message helpers moved here.
//

import Foundation

extension AccountEditor {
    private static let maximumValidationBodyBytes = 16 * 1024
    private static let maximumValidationMessageCharacters = 240

    func friendlyValidationMessage(for error: any Error) -> String {
        if let api = error as? CoderPadError {
            if api.isUnauthorized {
                return String(localized: """
                CoderPad rejected this key. API integration requires CoderPad Enterprise; \
                double-check that this key belongs to an Enterprise account and has not been revoked.
                """)
            }
            switch api {
            case .missingAPIKey:
                return String(localized: "Enter a CoderPad API key above.")

            case let .http(code, body):
                return friendlyHTTPValidationMessage(status: code, body: body)

            case .decode:
                return String(localized: """
                CoderPad returned something unexpected. Try again, and if it keeps happening, \
                regenerate the key.
                """)

            case .network:
                return api.errorDescription ?? String(localized: """
                Could not reach CoderPad. Check your internet connection and try again.
                """)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return String(localized: "Could not reach CoderPad. Check your internet connection and try again.")
        }
        return String(localized: "Could not validate this key. Try again.")
    }

    private func friendlyHTTPValidationMessage(status code: Int, body: String) -> String {
        switch code {
        case 404:
            return String(localized: """
            CoderPad could not find the API endpoint at this Server URL. \
            Hosted accounts should use https://app.coderpad.io.
            """)

        case 429:
            return String(localized: "CoderPad is rate-limiting validation right now. Try again in a moment.")

        case 500 ... 599:
            return String(localized: "CoderPad had a server error while validating this key. Try again shortly.")

        default:
            if let apiMessage = validationAPIMessage(from: body) {
                return String(localized: "CoderPad could not validate this key: \(apiMessage)")
            }
            return String(localized: "CoderPad could not validate this key (HTTP \(code)).")
        }
    }

    private func validationAPIMessage(from body: String) -> String? {
        guard body.utf8.count <= Self.maximumValidationBodyBytes,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        // Only documented human-readable fields are eligible. A generic `error`
        // value is frequently a machine code or proxy-controlled payload (#2876).
        for key in ["message", "error_description"] {
            guard let value = object[key] as? String else { continue }

            if let sanitized = Self.sanitizedValidationMessage(value), sanitized.lowercased() != "not found" {
                return sanitized
            }
        }
        return nil
    }

    private static func sanitizedValidationMessage(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("<"), !trimmed.contains(">") else { return nil }

        var result = ""
        var pendingSpace = false
        for character in trimmed {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            guard !character.unicodeScalars.contains(where: { scalar in
                let category = scalar.properties.generalCategory
                return category == .control || category == .format
            }) else { return nil }

            if pendingSpace {
                result.append(" ")
            }
            result.append(character)
            pendingSpace = false
        }
        guard !result.isEmpty else { return nil }

        if result.count > maximumValidationMessageCharacters {
            return String(result.prefix(maximumValidationMessageCharacters - 1)) + "…"
        }
        return result
    }
}
