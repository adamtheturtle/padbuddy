#!/usr/bin/env swift
//
// check-localization.swift
//
// Localization completeness gate. Exits non-zero if any user-facing string in a
// String Catalog (.xcstrings) is missing a complete translation for a required
// language. Wired into the swift-lint CI job (see .github/workflows/ci.yml) so a
// newly-added string cannot land on main without being localised.
//
// Policy — deliberately strict, but semantically correct:
//
//   * Required languages: `es`. This is the one locale the project ships as a
//     COMPLETE translation. `en` is the source language (its key is its own
//     value), and `en-GB` is a sparse regional OVERRIDE that intentionally falls
//     back to the `en` source for the strings it does not restate — demanding
//     100% coverage on either would be wrong, not stricter. To start enforcing a
//     new locale once it is meant to be complete, add it to `requiredLanguages`.
//
//   * A string is "localised" when its unit for the required language has a
//     non-empty value whose `state` is anything EXCEPT `new`. Machine
//     translation counts, but nontrivial prose copied unchanged from the source
//     language does not.
//
//   * `extractionState == "stale"` strings are ignored (Xcode prunes them on the
//     next build with SWIFT_EMIT_LOC_STRINGS) and `shouldTranslate == false`
//     strings are exempt (they are marked "don't translate" in the catalog).
//
//   * Every catalog unit shape is handled: `stringUnit`, `stringSet` (App
//     Shortcuts alternative phrasings), and `variations` (plural / device /
//     width), recursing into the variation cases.
//
// Run from the repository root: `swift scripts/check-localization.swift`.

import Foundation

/// Locales that must be fully translated. See the policy note above before adding.
let requiredLanguages = ["es"]

struct Violation {
    let file: String
    let key: String
    let language: String
    let reason: String
}

/// Directory names never worth scanning for catalogs (build output, VCS, vendored).
let skippedDirectories: Set<String> = ["DerivedData", "build_release", ".build", ".git", "cmark-gfm"]

/// Shipping catalogs are an explicit contract: discovery alone must not let deleting
/// an entire product catalog make the completeness score look better.
let requiredCatalogPaths = [
    "coderpad/Localizable.xcstrings",
    "coderpad/AppShortcuts.xcstrings",
    "coderpad/InfoPlist.xcstrings",
    "RecentPadsWidget/Localizable.xcstrings",
    "RecentPadsWidget/InfoPlist.xcstrings"
]

/// Repo-relative path for readable output and GitHub file annotations.
func relativePath(_ url: URL, root: URL) -> String {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return url.path.hasPrefix(rootPath) ? String(url.path.dropFirst(rootPath.count)) : url.path
}

func findCatalogs(root: URL) -> [URL] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var catalogs: [URL] = []
    for case let url as URL in enumerator {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            if skippedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
            }
            continue
        }
        if url.pathExtension == "xcstrings" {
            catalogs.append(url)
        }
    }
    return catalogs.sorted { $0.path < $1.path }
}

/// Returns a reason string when a single localization unit is not fully
/// translated, or nil when it is complete. Recurses through variation cases.
func isUnchangedProse(_ value: String, source: String) -> Bool {
    guard value == source else { return false }

    if value.contains("://") || (value.contains("@") && !value.contains(" ")) {
        return false
    }
    let languageNeutralValues: Set = ["CoderPad Screen", "%lld pad", "%lld pads"]
    if languageNeutralValues.contains(value) {
        return false
    }

    // Require at least two words so language-neutral labels, product names,
    // placeholders, URLs, and short terms that Spanish shares with English do
    // not become false positives.
    let wordCount = value.split(whereSeparator: { !$0.isLetter }).count
    return wordCount >= 2
}

func incompleteVariationReason(_ variations: [String: Any], source: String) -> String? {
    // e.g. { "plural": { "one": { "stringUnit": ... }, "other": { ... } } }
    for (_, axis) in variations {
        guard let cases = axis as? [String: Any] else { continue }

        for (_, caseValue) in cases {
            guard let caseUnit = caseValue as? [String: Any] else { continue }

            if let reason = incompleteReason(caseUnit, source: source) {
                return reason
            }
        }
    }
    return nil
}

func incompleteReason(_ unit: [String: Any], source: String) -> String? {
    if let stringUnit = unit["stringUnit"] as? [String: Any] {
        let value = stringUnit["value"] as? String ?? ""
        if value.isEmpty {
            return "empty value"
        }
        if stringUnit["state"] as? String == "new" {
            return "state=new"
        }
        return isUnchangedProse(value, source: source) ? "unchanged from source language" : nil
    }

    if let stringSet = unit["stringSet"] as? [String: Any] {
        let values = stringSet["values"] as? [String] ?? []
        if values.isEmpty || values.contains(where: \.isEmpty) {
            return "empty stringSet"
        }
        if stringSet["state"] as? String == "new" {
            return "state=new"
        }
        return nil
    }

    if let variations = unit["variations"] as? [String: Any] {
        return incompleteVariationReason(variations, source: source)
    }

    return "no translatable unit"
}

func check(catalog url: URL, root: URL) -> [Violation] {
    let path = relativePath(url, root: root)
    guard
        let data = try? Data(contentsOf: url),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let strings = object["strings"] as? [String: Any]
    else {
        return [Violation(file: path, key: "<file>", language: "-", reason: "could not parse catalog")]
    }

    var violations: [Violation] = []
    for (key, rawEntry) in strings {
        guard let entry = rawEntry as? [String: Any] else {
            violations.append(Violation(file: path, key: key, language: "-", reason: "malformed string entry"))
            continue
        }

        if entry["extractionState"] as? String == "stale" {
            continue
        }
        if entry["shouldTranslate"] as? Bool == false {
            continue
        }

        let localizations = entry["localizations"] as? [String: Any] ?? [:]
        for language in requiredLanguages {
            guard let unit = localizations[language] as? [String: Any] else {
                violations.append(Violation(file: path, key: key, language: language, reason: "missing"))
                continue
            }

            if let reason = incompleteReason(unit, source: key) {
                violations.append(Violation(file: path, key: key, language: language, reason: reason))
            }
        }
    }
    return violations
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalogs = findCatalogs(root: root)
var violations = catalogs.flatMap { check(catalog: $0, root: root) }
let discoveredPaths = Set(catalogs.map { relativePath($0, root: root) })
for path in requiredCatalogPaths where !discoveredPaths.contains(path) {
    violations.append(Violation(file: path, key: "<file>", language: "-", reason: "required catalog missing"))
}

// NSServices menu titles are nested values that Xcode does not reliably extract
// into InfoPlist.xcstrings. Require every declared title to be present explicitly.
let infoCatalogURL = root.appendingPathComponent("coderpad/InfoPlist.xcstrings")
let infoCatalogStrings: [String: Any] = {
    guard
        let data = try? Data(contentsOf: infoCatalogURL),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }

    return object["strings"] as? [String: Any] ?? [:]
}()

for plistPath in ["coderpad/Info.plist", "Info-AppStore.plist"] {
    let plistURL = root.appendingPathComponent(plistPath)
    guard
        let data = try? Data(contentsOf: plistURL),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        let services = plist["NSServices"] as? [[String: Any]]
    else {
        violations.append(Violation(file: plistPath, key: "NSServices", language: "-", reason: "could not parse"))
        continue
    }

    for service in services {
        guard
            let menuItem = service["NSMenuItem"] as? [String: Any],
            let title = menuItem["default"] as? String
        else { continue }

        if infoCatalogStrings[title] == nil {
            violations.append(Violation(
                file: "coderpad/InfoPlist.xcstrings",
                key: title,
                language: "es",
                reason: "NSServices title missing"
            ))
        }
    }
}

if violations.isEmpty {
    let languages = requiredLanguages.joined(separator: ", ")
    print("Localization gate passed: \(catalogs.count) catalog(s) fully translated for [\(languages)].")
    exit(0)
}

/// Group by file for a readable report, and emit a GitHub annotation per file.
let grouped = Dictionary(grouping: violations, by: { $0.file }).sorted { $0.key < $1.key }
print("Localization gate FAILED: \(violations.count) untranslated string(s).\n")
for (file, fileViolations) in grouped {
    print("\(file)  (\(fileViolations.count))")
    for violation in fileViolations.sorted(by: { $0.key < $1.key }) {
        print("  [\(violation.language)] \(violation.reason): \(violation.key)")
    }
    print("")
    // A file-level annotation (String Catalogs have no stable per-key line number).
    let summary = "\(fileViolations.count) string(s) missing a complete translation for a required locale"
    print("::error file=\(file)::\(summary)")
}

print("Add the missing translations to the String Catalog(s) above, then re-run.")
exit(1)
