//
//  MCPPadCode.swift
//  coderpad
//
//  The get_pad_code assembly for the in-app MCP server (#499): turn a fetched pad (and
//  its environments) into a compact { pad_id, title, files: [{ filename, language,
//  contents }] }. Kept as pure functions over already-decoded JSON so it's unit-tested
//  without network. Mirrors the standalone server's CoderPadMCPCore.padCodeFiles — #521
//  tracks unifying the two once the app can depend on the shared package.
//

import Foundation

nonisolated enum MCPPadCode {
    /// Common language → file extension mappings, used only to synthesize a filename for
    /// legacy single-file pads, which have no path of their own.
    private static let languageExtensions: [String: String] = [
        "python": "py", "python3": "py", "javascript": "js", "typescript": "ts",
        "java": "java", "ruby": "rb", "go": "go", "golang": "go", "c": "c",
        "cpp": "cpp", "c++": "cpp", "csharp": "cs", "c#": "cs", "php": "php",
        "swift": "swift", "kotlin": "kt", "rust": "rs", "sql": "sql",
        "scala": "scala", "r": "r", "perl": "pl", "bash": "sh", "shell": "sh"
    ]

    /// Synthesizes `main.<ext>` for a file with no path of its own. Falls back to the
    /// language name as the extension, then txt.
    static func synthesizedFilename(language: String?) -> String {
        guard let language, !language.isEmpty else { return "main.txt" }

        let key = language.lowercased()
        return "main.\(languageExtensions[key] ?? key)"
    }

    /// Truncates a file body to `maxChars`, noting how much was dropped. A nil/non-positive
    /// limit returns the body unchanged.
    static func truncate(_ body: String, to maxChars: Int?) -> String {
        guard let maxChars, maxChars > 0, body.count > maxChars else { return body }

        let dropped = body.count - maxChars
        return String(body.prefix(maxChars)) + "\n… [truncated, \(dropped) more characters]"
    }

    /// The numeric environment ids referenced by a pad, coercing string/int forms.
    static func environmentIDs(in pad: [String: Any]) -> [Int] {
        (pad["pad_environment_ids"] as? [Any])?
            .compactMap { ($0 as? Int) ?? Int("\($0)") } ?? []
    }

    /// A fetched multi-file environment: its id and decoded JSON object.
    struct Environment {
        let id: Int
        let object: [String: Any]
    }

    /// Assembles the file list for a pad. Multi-file environments take precedence; a
    /// legacy single-file pad's top-level "contents" is the fallback used only when no
    /// environment files were found.
    static func files(pad: [String: Any], environments: [Environment], maxFileChars: Int?) -> [[String: Any]] {
        var result: [[String: Any]] = []

        for environment in environments {
            let environmentLanguage = environment.object["language"] as? String
            let fileContents = environment.object["file_contents"] as? [[String: Any]] ?? []
            for file in fileContents {
                let language = (file["language"] as? String) ?? environmentLanguage
                var entry: [String: Any] = [
                    "filename": (file["path"] as? String) ?? synthesizedFilename(language: language),
                    "contents": truncate(file["contents"] as? String ?? "", to: maxFileChars),
                    "environment_id": environment.id
                ]
                if let language { entry["language"] = language }
                result.append(entry)
            }
        }

        if result.isEmpty, let contents = pad["contents"] as? String, !contents.isEmpty {
            let language = pad["language"] as? String
            var entry: [String: Any] = [
                "filename": synthesizedFilename(language: language),
                "contents": truncate(contents, to: maxFileChars)
            ]
            if let language { entry["language"] = language }
            result.append(entry)
        }

        return result
    }

    /// The full get_pad_code payload for a pad.
    static func payload(
        id: String, pad: [String: Any], environments: [Environment], maxFileChars: Int?
    ) -> [String: Any] {
        [
            "pad_id": id,
            "title": pad["title"] as? String ?? "",
            "files": files(pad: pad, environments: environments, maxFileChars: maxFileChars)
        ]
    }
}
