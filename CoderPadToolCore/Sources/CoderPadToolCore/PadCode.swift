//
//  PadCode.swift
//  CoderPadToolCore
//
//  The get_pad_code transform (#499): turn a fetched pad (and its environments) into
//  a compact { pad_id, title, files: [{ filename, language, contents }] }. Kept pure
//  — the executable does the fetching and hands the decoded JSON in here.
//

import Foundation

/// Parses a JSON object body into a dictionary, or nil if it isn't an object. Lets
/// the code tools pull fields out of the verbatim API JSON without binding to a rigid
/// Codable schema (keeping them resilient to API additions).
public func jsonObject(_ body: String) -> [String: Any]? {
    guard let data = body.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    return object
}

/// Truncates a file body to `maxChars`, appending a marker noting how much was
/// dropped. A nil/non-positive limit returns the body unchanged.
public func truncate(_ body: String, to maxChars: Int?) -> String {
    guard let maxChars, maxChars > 0, body.count > maxChars else { return body }

    let dropped = body.count - maxChars
    return String(body.prefix(maxChars)) + "\n… [truncated, \(dropped) more characters]"
}

/// A handful of common language → file extension mappings, used only to synthesize a
/// filename for legacy single-file pads, which have no path of their own.
public let languageExtensions: [String: String] = [
    "python": "py", "python3": "py", "javascript": "js", "typescript": "ts",
    "java": "java", "ruby": "rb", "go": "go", "golang": "go", "c": "c",
    "cpp": "cpp", "c++": "cpp", "csharp": "cs", "c#": "cs", "php": "php",
    "swift": "swift", "kotlin": "kt", "rust": "rs", "sql": "sql",
    "scala": "scala", "r": "r", "perl": "pl", "bash": "sh", "shell": "sh"
]

/// Synthesizes `main.<ext>` for a file that has no path of its own (legacy
/// single-file pads). Falls back to the language name as the extension, then txt.
public func synthesizedFilename(language: String?) -> String {
    guard let language, !language.isEmpty else { return "main.txt" }

    let key = language.lowercased()
    return "main.\(languageExtensions[key] ?? key)"
}

/// A fetched multi-file environment: its id and decoded JSON object.
public struct PadCodeEnvironment {
    public let id: Int
    public let object: [String: Any]

    public init(id: Int, object: [String: Any]) {
        self.id = id
        self.object = object
    }
}

/// The numeric environment ids referenced by a pad, coercing string/int forms.
public func environmentIDs(in pad: [String: Any]) -> [Int] {
    (pad["pad_environment_ids"] as? [Any])?
        .compactMap { ($0 as? Int) ?? Int("\($0)") } ?? []
}

/// Assembles the file list for a pad. Multi-file environments take precedence; a
/// legacy single-file pad's top-level "contents" is the fallback used only when no
/// environment files were found.
public func padCodeFiles(
    pad: [String: Any], environments: [PadCodeEnvironment], maxFileChars: Int?
) -> [[String: Any]] {
    var files: [[String: Any]] = []

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
            files.append(entry)
        }
    }

    if files.isEmpty, let contents = pad["contents"] as? String, !contents.isEmpty {
        let language = pad["language"] as? String
        var entry: [String: Any] = [
            "filename": synthesizedFilename(language: language),
            "contents": truncate(contents, to: maxFileChars)
        ]
        if let language { entry["language"] = language }
        files.append(entry)
    }

    return files
}

/// The full get_pad_code payload for a pad.
public func padCodePayload(
    id: String, pad: [String: Any], environments: [PadCodeEnvironment], maxFileChars: Int?
) -> [String: Any] {
    [
        "pad_id": id,
        "title": pad["title"] as? String ?? "",
        "files": padCodeFiles(pad: pad, environments: environments, maxFileChars: maxFileChars)
    ]
}
