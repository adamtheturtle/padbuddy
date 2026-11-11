//
//  DesignSystem+Languages.swift
//  coderpad
//

import Foundation

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
    nonisolated var coderPadLanguageDisplayName: String {
        guard utf8.prefix(129).count <= 128 else { return String(localized: "Unknown") }

        let lowered = lowercased()
        switch lowered {
        case "plaintext", "plain-text", "plain_text":
            return String(localized: "Plain text")
        default:
            if lowered.hasPrefix("multifile_") {
                // Strip every stacked prefix in one pass: language values come
                // from the API, and a crafted "multifile_multifile_…" string must
                // not recurse (and re-localize) once per prefix (#1702).
                var base = lowered[...]
                while base.hasPrefix("multifile_") {
                    base.removeFirst("multifile_".count)
                }
                return base.isEmpty
                    ? String(localized: "Project")
                    : String(localized: "\(String(base).coderPadLanguageDisplayName) Project",
                             comment: "A multi-file project environment for a language, e.g. \"Python Project\"")
            }

            let safe = ExternalText.singleLine(self, limit: 64)
            guard !safe.isEmpty else { return isEmpty ? "" : String(localized: "Unknown") }

            return ExternalText.singleLine(safe.languageDisplayName, limit: 64)
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
        "javascript", "typescript",
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
        "plaintext",
        "angular",
        "django",
        "flask-react",
        "gin",
        "jupyter-minimal",
        "jupyter-pyspark",
        "jupyter-pytorch",
        "jupyter-r",
        "jupyter-scipy",
        "jupyter-tensorflow",
        "jupyter-transformers",
        "kubernetes",
        "multifile_c",
        "multifile_cpp",
        "multifile_csharp",
        "multifile_go",
        "multifile_java",
        "multifile_kotlin",
        "multifile_php",
        "multifile_pyspark",
        "multifile_python",
        "multifile_pytorch",
        "multifile_ruby",
        "multifile_rust",
        "multifile_scala",
        "multifile_swift",
        "multifile_terraform",
        "multifile_typescript",
        "nextjs",
        "nodejs",
        "rails",
        "react",
        "react-native-web",
        "spring",
        "svelte",
        "universal",
        "vue"
    ]

    private static let pickerOptionSet = Set(pickerOptions)

    static func isPickerOption(_ language: String) -> Bool {
        pickerOptionSet.contains(language)
    }

    /// Returns whether a trimmed picker identifier is supported for pad creation,
    /// including project templates with their default starter files.
    static func canCreatePad(with language: String?) -> Bool {
        guard let language else { return false }

        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return pickerOptionSet.contains(normalized)
    }
}
