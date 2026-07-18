//
//  DesignSystem+Languages.swift
//  coderpad
//

import SwiftUI

extension InterviewType {
    /// SF Symbol paired with this type in metadata labels and filter menus.
    var systemImage: String {
        switch self {
        case .live: "dot.radiowaves.left.and.right"
        case .takeHome: "house"
        }
    }

    /// Standard metadata label for this type, used across list rows and detail
    /// headers. Informational, so it reads as restrained secondary text rather
    /// than a coloured pill.
    var chip: MetaLabel {
        MetaLabel(text: label, systemImage: systemImage)
    }
}

extension String {
    /// A human-friendly display name for a CoderPad language code, handling the two
    /// service-specific cases the shared `BuddyAppKit` catalog deliberately leaves
    /// app-side, then delegating everything else to `String.languageDisplayName`:
    ///
    /// - `plaintext` (and its `plain-text` / `plain_text` spellings) reads as the
    ///   localized "Plain text" rather than a bare title-cased "Plaintext".
    /// - `multifile_<lang>` names CoderPad's multi-file project environments, e.g.
    ///   `multifile_python` -> "Python Project" (localized), with a bare `multifile_`
    ///   falling back to "Project".
    ///
    /// Every other code, including the whole known-language table and the title-cased
    /// unknown-code fallback, comes straight from `BuddyAppKit`'s superset catalog.
    var coderPadLanguageDisplayName: String {
        let lowered = lowercased()
        switch lowered {
        case "plaintext", "plain-text", "plain_text":
            return String(localized: "Plain text")
        default:
            if lowered.hasPrefix("multifile_") {
                // Strip every stacked prefix in one pass: language values come
                // from the API, and a crafted "multifile_multifile_…" string must
                // not recurse (and re-localize) once per prefix (#1702).
                var base = lowered
                while base.hasPrefix("multifile_") {
                    base = String(base.dropFirst("multifile_".count))
                }
                return base.isEmpty
                    ? String(localized: "Project")
                    : String(localized: "\(base.coderPadLanguageDisplayName) Project",
                             comment: "A multi-file project environment for a language, e.g. \"Python Project\"")
            }

            return languageDisplayName
        }
    }
}

// MARK: - CoderPad links and languages

enum CoderPadLinks {
    static let apiSettings = URL.staticURL("https://app.coderpad.io/dashboard/settings")
    static let apiDocs = URL.staticURL("https://coderpad.io/resources/docs/coderpad-interview/api/")

    /// Where "Send Feedback…" delivers. This is an unofficial client, so reports go
    /// to the developer rather than CoderPad.
    static let feedbackEmail = "hello@adamdangoor.com"

    /// A pre-filled feedback email addressed to the developer. The app and macOS
    /// versions are appended so each report carries the context needed to act on it;
    /// the user types their message above the divider. Falls back to a bare mailto if
    /// the query somehow fails to encode.
    static var feedbackMailto: URL {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        // Label the OS line per platform: reports sent from iPad carried a
        // misleading "macOS:" diagnostic (#1705).
        #if os(macOS)
            let osLabel = "macOS"
        #else
            let osLabel = "iPadOS/iOS"
        #endif
        let body = """


        ---
        App version: \(version) (\(build))
        \(osLabel): \(osVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "PadBuddy for Mac feedback"),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            return url
        }
        // `feedbackEmail` is a compile-time-constant valid address, so the mailto URL
        // always parses; the apiDocs fallback only keeps the return non-optional
        // without a force-unwrap.
        return URL(string: "mailto:\(feedbackEmail)") ?? Self.apiDocs
    }
}

enum CoderPadLanguages {
    static let pickerOptions: [String] = [
        "python3", "python2",
        "javascript", "typescript", "nodejs",
        "swift",
        "go",
        "rust",
        "java", "kotlin", "scala",
        "ruby",
        "c", "cpp", "csharp", "objective-c",
        "php",
        "r",
        "sql", "mysql", "postgresql",
        "bash", "shell",
        "elixir", "erlang", "haskell", "perl", "lua", "dart", "clojure", "ocaml", "fsharp",
        "julia", "solidity", "tcl", "verilog",
        "html", "css", "markdown",
        "plaintext"
    ]

    /// Returns whether `language` can be used with CoderPad's pad-creation API:
    /// only trimmed, picker-supported codes qualify. Project environments are
    /// displayed for existing pads/questions, but new ones must be created in the
    /// web app; unknown (#1703) and whitespace-only (#1704) values used to pass
    /// this gate and pre-fill the create flow with a value the server rejects.
    static func canCreatePad(with language: String?) -> Bool {
        guard let language else { return false }

        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pickerOptions.contains(normalized)
    }

    /// Where to create the project and framework environments (React, Django, Rails,
    /// and so on) that this list omits. CoderPad's pad-creation API only mints
    /// single-file language environments, so those can't be made from here; they're
    /// created in the web app instead.
    static let projectEnvironmentsURL = URL.staticURL("https://app.coderpad.io")
}
