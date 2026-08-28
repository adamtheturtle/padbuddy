#!/usr/bin/env swift
//
// Detect user-facing Swift string literals that are absent from every shipping
// String Catalog. This complements check-localization.swift: that checker proves
// catalog translations are complete; this one proves likely UI source reaches a
// catalog at all. The scanner is intentionally narrow and allowlist-backed.

import Foundation

struct Finding: Hashable {
    let path: String
    let line: Int
    let value: String
    let context: String
}

struct AllowlistEntry: Decodable {
    let path: String
    let value: String
    let reason: String
}

let arguments = Array(CommandLine.arguments.dropFirst())
let repositoryRoot = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)
    .standardizedFileURL.resolvingSymlinksInPath()
let allowlistURL = repositoryRoot.appendingPathComponent(".localization-source-allowlist.json")
let sourceDirectories = ["PadBuddy", "WatchApp", "TVApp", "RecentPadsWidget"]
let skippedDirectoryNames: Set<String> = ["DerivedData", ".build", ".git", "Tests", "Preview Content"]

func relativePath(_ url: URL) -> String {
    func canonical(_ path: String) -> String {
        path.hasPrefix("/private/var/") ? String(path.dropFirst("/private".count)) : path
    }
    let rootPath = canonical(repositoryRoot.path)
    let urlPath = canonical(url.path)
    let prefix = rootPath + "/"
    return urlPath.hasPrefix(prefix) ? String(urlPath.dropFirst(prefix.count)) : urlPath
}

func files(withExtension fileExtension: String, below roots: [URL]) -> [URL] {
    roots.flatMap { root -> [URL] in
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true {
                if skippedDirectoryNames.contains(url.lastPathComponent) {
                    enumerator.skipDescendants()
                }
            } else if url.pathExtension == fileExtension {
                result.append(url)
            }
        }
        return result
    }.sorted { $0.path < $1.path }
}

func catalogKeys() throws -> Set<String> {
    let catalogs = files(withExtension: "xcstrings", below: [repositoryRoot])
    var keys = Set<String>()
    for catalog in catalogs {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog))
        guard let root = object as? [String: Any], let strings = root["strings"] as? [String: Any] else { continue }

        keys.formUnion(strings.keys)
    }
    return keys
}

func loadAllowlist() throws -> [AllowlistEntry] {
    guard FileManager.default.fileExists(atPath: allowlistURL.path) else { return [] }

    let entries = try JSONDecoder().decode([AllowlistEntry].self, from: Data(contentsOf: allowlistURL))
    for entry in entries where entry.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw NSError(domain: "LocalizationSourceAudit", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Allowlist entry for \(entry.path) has no reason"])
    }
    return entries
}

/// Calls whose first literal argument is normally presented to a user or VoiceOver.
let userFacingCalls = [
    "Text", "Button", "Label", "Link", "Menu", "Picker", "Toggle", "Section",
    "TextField", "SecureField", "ProgressView", "ContentUnavailableView", "CommandMenu",
    "navigationTitle", "accessibilityLabel", "accessibilityValue", "accessibilityHint", "help"
]
let callAlternation = userFacingCalls.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
let namedPresentationPattern = #"\b(?:var|let)\s+\w*(?:label|title|message|status|hint|help|error)\w*"#
    + #"\s*:\s*(?:String|LocalizedStringKey)\s*(?:=|\{\s*(?:return\s+)?)"#
    + #"\s*"((?:\\.|[^"\\])*)""#
let patterns = [
    #"(?:\b|\.)(?:"# + callAlternation + #")\s*\(\s*"((?:\\.|[^"\\])*)""#,
    namedPresentationPattern
]

/// Turns a captured Swift string literal body into the string it denotes.
///
/// Decoded directly rather than through `JSONDecoder`. Swift's escape set is not JSON's:
/// `\u{1F600}`, `\0`, and `\\` are all valid in a Swift literal and all invalid JSON, so
/// `try?` yielded nil and the caller's `guard` dropped the finding — a silent false
/// negative in a gate, with nothing to say a literal had been skipped (issue #4758).
func decodedLiteral(_ captured: String) -> String? {
    guard !captured.contains("\\(") else { return nil }

    var result = ""
    var characters = Array(captured)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        guard character == "\\" else {
            result.append(character)
            index += 1
            continue
        }

        index += 1
        guard index < characters.count else { return nil }

        let escape = characters[index]
        index += 1
        switch escape {
        case "n": result.append("\n")
        case "t": result.append("\t")
        case "r": result.append("\r")
        case "0": result.append("\0")
        case "\\": result.append("\\")
        case "\"": result.append("\"")
        case "'": result.append("'")
        case "u":
            // Swift spells this `\u{...}`; JSON spells it `\uXXXX`.
            guard index < characters.count, characters[index] == "{",
                  let close = characters[index...].firstIndex(of: "}") else { return nil }

            let digits = String(characters[(index + 1) ..< close])
            guard let value = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(value) else {
                return nil
            }

            result.unicodeScalars.append(scalar)
            index = close + 1
        default:
            // An escape this does not know is a literal it cannot read, and reporting it
            // as "no literal here" is what made the gate silently incomplete.
            return nil
        }
    }
    return result
}

func lineNumber(at location: Int, in text: String) -> Int {
    let index = String.Index(utf16Offset: location, in: text)
    return text[..<index].reduce(1) { count, character in
        character == "\n" ? count + 1 : count
    }
}

func findings(in sourceURL: URL, catalogKeys: Set<String>) throws -> Set<Finding> {
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let fullRange = NSRange(location: 0, length: source.utf16.count)
    var findings = Set<Finding>()
    for pattern in patterns {
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        for match in regex.matches(in: source, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: source),
                  let value = decodedLiteral(String(source[range])),
                  !value.isEmpty,
                  !catalogKeys.contains(value) else { continue }

            // Xcode extracts an adjacent `"first " + "second"` expression as one
            // catalog key. Do not report only its first fragment as a false positive;
            // exportLocalizations remains the authoritative check for that expression.
            let suffixLocation = NSMaxRange(match.range(at: 1)) + 1 // closing quote
            if suffixLocation < source.utf16.count {
                let suffixIndex = String.Index(utf16Offset: suffixLocation, in: source)
                let suffix = source[suffixIndex...].drop(while: \.isWhitespace)
                if suffix.first == "+" {
                    continue
                }
            }
            guard let matchRange = Range(match.range, in: source) else { continue }

            let matchText = source[matchRange]
            findings.insert(Finding(
                path: relativePath(sourceURL),
                line: lineNumber(at: match.range.location, in: source),
                value: value,
                context: String(matchText.prefix(120)).replacingOccurrences(of: "\n", with: " ")
            ))
        }
    }
    return findings
}

do {
    let keys = try catalogKeys()
    let allowlist = try loadAllowlist()
    let allowed = Set(allowlist.map { "\($0.path)\u{0}\($0.value)" })
    let sourceRoots = sourceDirectories.map { repositoryRoot.appendingPathComponent($0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    let swiftFiles = files(withExtension: "swift", below: sourceRoots)
    let allFindings = try swiftFiles.reduce(into: Set<Finding>()) { result, url in
        try result.formUnion(findings(in: url, catalogKeys: keys))
    }
    let violations = allFindings.filter { !allowed.contains("\($0.path)\u{0}\($0.value)") }
        .sorted { ($0.path, $0.line, $0.value) < ($1.path, $1.line, $1.value) }

    if violations.isEmpty {
        print("Localized source audit passed (\(swiftFiles.count) Swift files, \(keys.count) catalog keys).")
    } else {
        for finding in violations {
            let annotation = "::error file=\(finding.path),line=\(finding.line)::"
                + "User-facing literal is absent from String Catalogs: \(finding.value)"
            print(annotation)
            print("  \(finding.context)")
        }
        print("Add localization or a reviewed path/value/reason entry to .localization-source-allowlist.json.")
        exit(1)
    }
} catch {
    fputs("error: localized source audit failed: \(error.localizedDescription)\n", stderr)
    exit(2)
}
