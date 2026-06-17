//
//  CoderPadAPI+Organization.swift
//  coderpad
//
//  Organization, quota, and the user-facing `CoderPadError`.
//

import Foundation

nonisolated struct Organization: Decodable, Hashable {
    let id: Int
    let organizationName: String
    let userCount: Int?
    let users: [OrganizationUser]
    let teams: [PadTeam]
    let organizationDefaultLanguage: String?
    let singleSignOnSupported: Bool?
    /// URL of the organization's SSO sign-in portal, when SSO is supported.
    let singleSignInURL: String?

    enum CodingKeys: String, CodingKey {
        case id, users, teams
        case organizationName = "organization_name"
        case userCount = "user_count"
        case organizationDefaultLanguage = "organization_default_language"
        case singleSignOnSupported = "single_sign_on_supported"
        case singleSignInURL = "single_sign_in_url"
    }
}

nonisolated struct OrganizationUser: Decodable, Identifiable, Hashable {
    var id: String {
        email
    }

    let email: String
    let name: String?
    let teams: [String]?
    let padsCreated: Int?

    enum CodingKeys: String, CodingKey {
        case email, name, teams
        case padsCreated = "pads_created"
    }
}

nonisolated struct OrganizationStats: Decodable, Hashable {
    let startTime: Date?
    let endTime: Date?
    let padsCreated: Int
    let users: [OrganizationUser]

    enum CodingKeys: String, CodingKey {
        case users
        case startTime = "start_time"
        case endTime = "end_time"
        case padsCreated = "pads_created"
    }
}

nonisolated struct Quota: Decodable, Hashable {
    let trialExpiresAt: Date?
    let padsUsed: Int?
    let quotaReset: Date?
    let unlimited: Bool?
    let overagesEnabled: Bool?
    /// Pads left in the current billing cycle. Absent (nil) when `unlimited` is true.
    let padsRemaining: Int?
    /// Total pads allocated for the billing cycle. Absent (nil) when `unlimited` is true.
    let billingCyclePadLimit: Int?

    enum CodingKeys: String, CodingKey {
        case unlimited
        case trialExpiresAt = "trial_expires_at"
        case padsUsed = "pads_used"
        case quotaReset = "quota_reset_at"
        case overagesEnabled = "overages_enabled"
        case padsRemaining = "pads_remaining"
        case billingCyclePadLimit = "billing_cycle_pad_limit"
    }
}

// MARK: - Errors

enum CoderPadError: LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case decode(String)
    /// A transport-level failure (offline, timeout, unreachable host) before any HTTP
    /// response arrived. Mapped to a plain-language sentence rather than surfacing the
    /// raw `URLError`, which on the sandbox can read as a cryptic "could not connect".
    case network(URLError)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            String(localized: "Missing API key. Open Settings to add an account.")
        case let .http(code, body):
            Self.message(forStatus: code, body: body)
        case let .decode(detail):
            String(localized: "Couldn't read response: \(detail)")
        case let .network(urlError):
            Self.message(forURLError: urlError)
        }
    }

    /// A human-facing sentence for a transport failure. Groups the common URL error
    /// codes (offline, timeout, unreachable) into clear, actionable messages.
    private static func message(forURLError error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            String(localized: "You appear to be offline. Check your internet connection and try again.")
        case .timedOut:
            String(localized: "The request timed out. Check your connection and try again.")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            String(localized: "Couldn't reach CoderPad. Check your connection and try again.")
        default:
            String(localized: "A network error occurred. Check your connection and try again.")
        }
    }

    /// A human-facing sentence for an HTTP failure. Deliberately never echoes the raw
    /// response body — surfacing `{"status":404,"error":"Not Found"}` in an alert leaks
    /// the transport layer into the UI. Known status codes get a plain-language
    /// explanation; for anything else we prefer a message the API itself supplied,
    /// falling back to a generic line that keeps the code for a bug report.
    private static func message(forStatus code: Int, body: String) -> String {
        switch code {
        case 401, 403:
            return String(localized: "You're not authorized. Check this account's API key in Settings.")
        case 404:
            return String(localized: "The server couldn't find that. It may have already been deleted.")
        case 429:
            return String(localized: "CoderPad is rate-limiting requests right now. Try again in a moment.")
        case 500 ... 599:
            return String(localized: "CoderPad had a server error. Please try again shortly.")
        default:
            if let apiMessage = apiMessage(from: body) { return apiMessage }
            return String(localized: "The request failed (HTTP \(code)).")
        }
    }

    /// Pulls a human-readable message out of an error response body, if it carries one.
    /// CoderPad returns errors as `{"message": …}` or `{"error": …}`; we ignore the bare
    /// `status`/`error` boilerplate (e.g. "Not Found") so only a real explanation shows.
    private static func apiMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        for key in ["message", "error_description", "error"] {
            if let value = object[key] as? String,
               !value.isEmpty,
               value.caseInsensitiveCompare("Not Found") != .orderedSame {
                return value
            }
        }
        return nil
    }

    var isUnauthorized: Bool {
        if case .http(401, _) = self { return true }
        if case .http(403, _) = self { return true }
        return false
    }
}
