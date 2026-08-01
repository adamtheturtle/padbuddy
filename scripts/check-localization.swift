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
let completedLocalizationStates: Set<String> = ["translated", "machine_translated"]

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

func placeholderSignature(_ value: String) -> [String] {
    let pattern = #"%(?!#@|arg)(?:(\d+)\$)?[-+#0 ']*(?:\d+|\*)?(?:\.\*|\.\d+)?"#
        + #"(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp])"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

    let range = NSRange(value.startIndex..., in: value)
    var implicitPosition = 0
    return regex.matches(in: value, range: range).compactMap { match in
        implicitPosition += 1
        guard let conversionRange = Range(match.range(at: 3), in: value) else { return nil }

        let explicitPosition = Range(match.range(at: 1), in: value).map { String(value[$0]) }
        let modifier = Range(match.range(at: 2), in: value).map { String(value[$0]) } ?? ""
        return "\(explicitPosition ?? String(implicitPosition)):\(modifier)\(value[conversionRange])"
    }.sorted()
}

func localizedPlaceholderSignature(_ value: String, unit: [String: Any]) -> [String] {
    var signature = placeholderSignature(value)
    let substitutions = unit["substitutions"] as? [String: Any] ?? [:]
    for (name, rawSubstitution) in substitutions where value.contains("%#@\(name)@") {
        guard let substitution = rawSubstitution as? [String: Any],
              let argument = substitution["argNum"] as? Int,
              let format = substitution["formatSpecifier"] as? String else { continue }

        signature.append("\(argument):\(format)")
    }
    return signature.sorted()
}

func placeholderMismatch(_ value: String, source: String, unit: [String: Any] = [:]) -> Bool {
    localizedPlaceholderSignature(value, unit: unit) != placeholderSignature(source)
}

func incompleteVariationReason(_ variations: [String: Any], source: String, sourceSet: [String]?) -> String? {
    // e.g. { "plural": { "one": { "stringUnit": ... }, "other": { ... } } }
    guard !variations.isEmpty else { return "empty variations" }

    for (axisName, axis) in variations {
        guard let cases = axis as? [String: Any] else { return "malformed variation axis \(axisName)" }

        if axisName == "plural", cases["other"] == nil {
            return "plural variation missing other case"
        }

        for (caseName, caseValue) in cases {
            guard let caseUnit = caseValue as? [String: Any] else {
                return "malformed \(axisName) variation case \(caseName)"
            }

            if let reason = incompleteReason(caseUnit, source: source, sourceSet: sourceSet) {
                return reason
            }
        }
    }
    return nil
}

func incompleteStringUnitReason(_ stringUnit: [String: Any], source: String, container: [String: Any]) -> String? {
    let value = stringUnit["value"] as? String ?? ""
    if value.isEmpty {
        return "empty value"
    }
    guard let state = stringUnit["state"] as? String else { return "missing workflow state" }
    guard completedLocalizationStates.contains(state) else { return "state=\(state)" }

    if placeholderMismatch(value, source: source, unit: container) {
        return "format placeholders differ from source language"
    }
    return isUnchangedProse(value, source: source) ? "unchanged from source language" : nil
}

func incompleteStringSetReason(_ stringSet: [String: Any], source: String, sourceSet: [String]?) -> String? {
    let values = stringSet["values"] as? [String] ?? []
    if values.isEmpty || values.contains(where: \.isEmpty) {
        return "empty stringSet"
    }
    guard let state = stringSet["state"] as? String else { return "missing workflow state" }
    guard completedLocalizationStates.contains(state) else { return "state=\(state)" }

    let sourceValues = sourceSet ?? [source]
    for (index, value) in values.enumerated() where index < sourceValues.count {
        if placeholderMismatch(value, source: sourceValues[index]) {
            return "stringSet format placeholders differ from source language"
        }
    }
    if values.contains(where: { sourceValues.contains($0) && isUnchangedProse($0, source: $0) }) {
        return "stringSet unchanged from source language"
    }
    return nil
}

func incompleteReason(_ unit: [String: Any], source: String, sourceSet: [String]? = nil) -> String? {
    if let stringUnit = unit["stringUnit"] as? [String: Any] {
        return incompleteStringUnitReason(stringUnit, source: source, container: unit)
    }
    if let stringSet = unit["stringSet"] as? [String: Any] {
        return incompleteStringSetReason(stringSet, source: source, sourceSet: sourceSet)
    }

    if let variations = unit["variations"] as? [String: Any] {
        return incompleteVariationReason(variations, source: source, sourceSet: sourceSet)
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
    let sourceLanguage = object["sourceLanguage"] as? String ?? "en"
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
        let sourceUnit = localizations[sourceLanguage] as? [String: Any]
        let sourceStringSet = (sourceUnit?["stringSet"] as? [String: Any])?["values"] as? [String]
        for language in requiredLanguages {
            guard let unit = localizations[language] as? [String: Any] else {
                violations.append(Violation(file: path, key: key, language: language, reason: "missing"))
                continue
            }

            if let reason = incompleteReason(unit, source: key, sourceSet: sourceStringSet) {
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
