//
//  CoderPadKit+Presentation.swift
//  coderpad
//
//  The app-side presentation overlay over the locale-free `CoderPadKit` types: the
//  human-facing labels, SF Symbols, and localized error sentences. These live in the
//  app (not the package) so the existing String Catalog translations keep working and
//  the library stays presentation-free and locale-free (#569).
//

import CoderPadKit
import Foundation

extension InterviewType {
    /// Human-facing label for filter menus and badges. Localized at the source so
    /// every `Text(type.label)` / `MetaLabel(text:)` site renders in the user's
    /// language even though those views take a plain `String` (#111).
    var label: String {
        switch self {
        case .live: String(localized: "Live")
        case .takeHome: String(localized: "Take-home")
        }
    }
}

extension PadState {
    /// Human-facing label for badges and filter menus. Localized at the source so
    /// `StateBadge` / `MetaLabel` (which take a plain `String`) still render in the
    /// user's language (#111). `.other` carries an unrecognized API value, so it's
    /// surfaced verbatim rather than translated.
    var label: String {
        switch self {
        case .active: String(localized: "Active")
        case .ended: String(localized: "Ended")
        case .pending: String(localized: "Pending")
        case .deleted: String(localized: "Deleted")
        case let .other(raw): raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// SF Symbol paired with this state when it's rendered as restrained
    /// metadata (every state except the prominent "Active"; see `StateBadge`).
    var systemImage: String {
        switch self {
        case .active: "dot.radiowaves.left.and.right"
        case .ended: "checkmark.circle"
        case .pending: "clock"
        case .deleted: "trash"
        case .other: "circle"
        }
    }
}

// MARK: - Localized errors

/// Retroactive `LocalizedError` conformance so `CoderPadError` presents user-facing,
/// localized sentences in the app while staying a raw, locale-free type in the package.
extension CoderPadError: @retroactive LocalizedError {
    public var errorDescription: String? {
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
    /// response body - surfacing `{"status":404,"error":"Not Found"}` in an alert leaks
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
}
