//
//  WidgetSharedSnapshot.swift
//  RecentPadsWidget
//
//  The widget side of the data contract shared with the app. The app writes recent
//  pads into the App Group container (see the app's `WidgetPadSnapshot.swift` /
//  `WidgetSync.swift`); this reads them back. The two definitions are deliberately
//  kept in lock-step on the JSON shape (property names) rather than sharing a file,
//  so the widget target stays free of any app dependency.
//

import Foundation

/// A minimal, dependency-free projection of a pad for display in the widget.
struct WidgetPadSnapshot: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let language: String?
    let updatedAt: Date?
}

/// Reads the recent-pads snapshot from the App Group container shared with the app.
enum WidgetSharedStore {
    /// Must match the app's `WidgetSharedStore.appGroupID`. If `containerURL` ever
    /// returns nil at runtime, this likely needs the team-id prefixed form
    /// (`6L9H6Q8CUF.group.ptn.coderpad`) on macOS.
    static let appGroupID = "group.ptn.coderpad"

    /// The widget's kind, shared with the app's reload logic.
    static let widgetKind = "RecentPadsWidget"

    private static let fileName = "recent-pads.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    /// The last snapshot the app wrote, or an empty list when none exists yet.
    static func load() -> [WidgetPadSnapshot] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([WidgetPadSnapshot].self, from: data)) ?? []
    }
}

// MARK: - Display helpers

extension WidgetPadSnapshot {
    /// A human-friendly language name (e.g. "JavaScript"), or `nil` when the pad has
    /// no language. Mirrors the app's `languageDisplayName`.
    var languageLabel: String? {
        guard let language, !language.isEmpty else { return nil }
        return language.languageDisplayName
    }

    /// A short relative description of the last update, e.g. "2 hr. ago". `nil` when no
    /// timestamp is available. Computed at render time, so the widget refreshes
    /// periodically (see the timeline provider) to keep it from going stale.
    var relativeUpdated: String? {
        guard let updatedAt else { return nil }
        return updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    /// A single spoken label combining title, language, and last update for VoiceOver.
    var accessibilityDescription: String {
        var parts = [title]
        if let languageLabel { parts.append(languageLabel) }
        if let relativeUpdated { parts.append("updated \(relativeUpdated)") }
        return parts.joined(separator: ", ")
    }
}

extension String {
    /// Friendly casing for CoderPad language codes. Duplicated from the app's
    /// `DesignSystem` extension so the widget target stays dependency-free.
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
        case "plaintext", "plain-text", "plain_text": return "Plain text"
        default:
            let lowered = lowercased()
            if lowered.hasPrefix("multifile_") {
                let base = String(lowered.dropFirst("multifile_".count))
                return base.isEmpty ? "Project" : base.languageDisplayName + " Project"
            }
            guard !isEmpty else { return self }
            return prefix(1).uppercased() + dropFirst()
        }
    }
}
