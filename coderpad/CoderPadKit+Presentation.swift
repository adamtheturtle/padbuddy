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
    /// The catalog lookups happen once per process rather than per access: this is
    /// read from row badges and metadata on every body pass, so a `String(localized:)`
    /// inside meant a String Catalog lookup for every rendered row (#2441).
    private enum Labels {
        static let live = String(localized: "Live")
        static let takeHome = String(localized: "Take-home")
    }

    var label: String {
        switch self {
        case .live: Labels.live
        case .takeHome: Labels.takeHome
        }
    }
}

extension Pad {
    /// The pad's web URL with a guaranteed value: the API's `url` string when it
    /// parses, otherwise `{base}/{id}` (the canonical pad address). Quick-create
    /// flows use this so a successfully created pad can always be opened, instead of
    /// ending silently when the response's `url` is absent or malformed (#781).
    func webURL(fallbackBase: URL) -> URL? {
        if let webURL,
           webURL.scheme?.lowercased() == "https",
           webURL.host?.isEmpty == false {
            return webURL
        }
        return Self.fallbackWebURL(id: id, base: fallbackBase)
    }

    static func fallbackWebURL(id: String, base: URL) -> URL? {
        guard !id.isEmpty, id.count <= 200, id != ".", id != "..",
              !id.contains("/"), !id.contains("\\"),
              !id.unicodeScalars.contains(where: { scalar in
                  switch scalar.properties.generalCategory {
                  case .control, .format, .privateUse, .surrogate, .unassigned: true
                  default: false
                  }
              }),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.host?.isEmpty == false,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil
        else { return nil }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encodedID = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }

        let basePath = components.percentEncodedPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, encodedID]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return components.url
    }
}

extension PadState {
    /// Human-facing label for badges and filter menus. Localized at the source so
    /// `StateBadge` / `MetaLabel` (which take a plain `String`) still render in the
    /// user's language (#111). `.other` carries an unrecognized API value, so it's
    /// surfaced verbatim rather than translated.
    /// Resolved once, for the same reason as `InterviewType.Labels` (#2441).
    private enum Labels {
        static let active = String(localized: "Active")
        static let ended = String(localized: "Ended")
        static let pending = String(localized: "Pending")
        static let deleted = String(localized: "Deleted")
        static let unknown = String(localized: "Unknown")
    }

    var label: String {
        switch self {
        case .active: Labels.active
        case .ended: Labels.ended
        case .pending: Labels.pending
        case .deleted: Labels.deleted
        case let .other(raw): Self.safeOtherLabel(raw)
        }
    }

    private static func safeOtherLabel(_ raw: String) -> String {
        let visible = raw.unicodeScalars.map { scalar -> Character in
            switch scalar.properties.generalCategory {
            case .control, .format, .privateUse, .surrogate, .unassigned: " "
            default: scalar == "_" ? " " : Character(scalar)
            }
        }
        let normalized = String(visible)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
        guard !normalized.isEmpty else { return Labels.unknown }

        return String(normalized.prefix(40)).capitalized
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
            String(localized: "Could not read response: \(detail)")
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
            String(localized: "Could not reach CoderPad. Check your connection and try again.")
        case .secureConnectionFailed, .serverCertificateHasBadDate,
             .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            String(localized: "Could not establish a secure connection. Check the server address and certificate.")
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
            return String(localized: "You are not authorized. Check this account's API key in Settings.")
        case 404:
            return String(localized: "The server could not find that. It may have already been deleted.")
        case 429:
            return String(localized: "CoderPad is rate-limiting requests right now. Try again in a moment.")
        case 500 ... 599:
            return String(localized: "CoderPad had a server error. Please try again shortly.")
        default:
            if let apiMessage = apiMessage(from: body) {
                return apiMessage
            }
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

        var candidates = [object["message"], object["error_description"]]
        if let error = object["error"] as? [String: Any] {
            candidates += [error["message"], error["detail"], error["description"]]
        } else {
            candidates.append(object["error"])
        }
        // Some endpoints return `errors: [{message: ...}]`. Inspect only a small
        // prefix and known fields rather than recursively walking server-controlled
        // JSON with unbounded depth or breadth (#1541).
        if let errors = object["errors"] as? [Any] {
            for error in errors.prefix(10) {
                if let envelope = error as? [String: Any] {
                    candidates += [envelope["message"], envelope["detail"], envelope["description"]]
                } else {
                    candidates.append(error)
                }
            }
        }

        for case let value as String in candidates {
            if let message = sanitizedAPIMessage(value),
               message.caseInsensitiveCompare("Not Found") != .orderedSame {
                return message
            }
        }
        return nil
    }

    private static func sanitizedAPIMessage(_ value: String) -> String? {
        let maximumCharacters = 300
        var result = ""
        var pendingSpace = false
        for character in value.trimmingCharacters(in: .whitespacesAndNewlines) {
            if character.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            guard !character.unicodeScalars.contains(where: { scalar in
                let category = scalar.properties.generalCategory
                return category == .control || category == .format
            }) else { continue }

            if pendingSpace {
                result.append(" ")
            }
            result.append(character)
            pendingSpace = false
            if result.count == maximumCharacters {
                result.removeLast()
                result.append("…")
                break
            }
        }
        return result.isEmpty ? nil : result
    }
}
