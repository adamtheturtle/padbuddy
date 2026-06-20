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
    var languageDisplayName: String {
        switch lowercased() {
        case "python": return "Python"
        case "python2": return "Python 2"
        case "python3": return "Python 3"
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "node", "node.js", "nodejs": return "Node.js"
        case "swift": return "Swift"
        case "go", "golang": return "Go"
        case "rust": return "Rust"
        case "java": return "Java"
        case "kotlin": return "Kotlin"
        case "ruby": return "Ruby"
        case "c": return "C"
        case "cpp", "c++": return "C++"
        case "csharp", "c#": return "C#"
        case "objective-c", "objc": return "Objective-C"
        case "php": return "PHP"
        case "html": return "HTML"
        case "css": return "CSS"
        case "sql": return "SQL"
        case "mysql": return "MySQL"
        case "postgresql", "postgres": return "PostgreSQL"
        case "bash": return "Bash"
        case "shell", "sh": return "Shell"
        case "r": return "R"
        case "scala": return "Scala"
        case "elixir": return "Elixir"
        case "erlang": return "Erlang"
        case "haskell": return "Haskell"
        case "perl": return "Perl"
        case "lua": return "Lua"
        case "dart": return "Dart"
        case "clojure": return "Clojure"
        case "ocaml": return "OCaml"
        case "f#", "fsharp": return "F#"
        case "julia": return "Julia"
        case "markdown": return "Markdown"
        case "solidity": return "Solidity"
        case "tcl": return "Tcl"
        case "verilog": return "Verilog"
        case "plaintext", "plain-text", "plain_text": return String(localized: "Plain text")
        default:
            let lowered = lowercased()
            if lowered.hasPrefix("multifile_") {
                let base = String(lowered.dropFirst("multifile_".count))
                return base.isEmpty
                    ? String(localized: "Project")
                    : String(localized: "\(base.languageDisplayName) Project",
                             comment: "A multi-file project environment for a language, e.g. \"Python Project\"")
            }
            guard !isEmpty else { return self }

            return prefix(1).uppercased() + dropFirst()
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
        let body = """


        ---
        App version: \(version) (\(build))
        macOS: \(osVersion)
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

    /// Where to create the project and framework environments (React, Django, Rails,
    /// and so on) that this list omits. CoderPad's pad-creation API only mints
    /// single-file language environments, so those can't be made from here; they're
    /// created in the web app instead.
    static let projectEnvironmentsURL = URL.staticURL("https://app.coderpad.io")
}
