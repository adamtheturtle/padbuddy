#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let projectPath = "PadBuddy.xcodeproj/project.xcproj"
let projectURL = root.appendingPathComponent(projectPath)
guard let project = try? String(contentsOf: projectURL, encoding: .utf8) else {
    fail("Could not read \(projectPath)")
}

let entitlementPattern = #""CODE_SIGN_ENTITLEMENTS(?:\[[^\]]+\])*": "([^"]+)""#
guard let entitlementRegex = try? NSRegularExpression(pattern: entitlementPattern) else {
    fail("Could not create entitlement build-setting matcher")
}

let projectRange = NSRange(project.startIndex..., in: project)
let entitlementFiles = Set(entitlementRegex.matches(in: project, range: projectRange).compactMap { match -> String? in
    guard let range = Range(match.range(at: 1), in: project) else { return nil }

    return String(project[range])
})
guard !entitlementFiles.isEmpty else {
    fail("No entitlement files are selected by \(projectPath)")
}

for path in entitlementFiles.sorted() {
    let url = root.appendingPathComponent(path)
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let dictionary = plist as? [String: Any] else {
        fail("Could not read entitlements at \(path)")
    }

    if dictionary["keychain-access-groups"] != nil {
        fail("\(path) declares keychain-access-groups; credentials must remain app-private")
    }
}

let privateEnumPrefix = #"private(?:\s+[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?)*\s+enum\s+"#
struct SourcePolicy {
    let path: String
    let required: [String]
    let patterns: [String]
}

/// Every shipping source that may perform Security-framework item operations. Auditing a
/// hard-coded list alone meant a NEW file could add a credential store — with an explicit
/// access group or weaker accessibility — and the gate still passed as long as the named
/// files were unchanged (issue #4589). Discovery below fails on anything not listed here,
/// so adding a store is a deliberate review step.
let auditedStorePaths: Set<String> = [
    "PadBuddy/Accounts+Keychain.swift",
    "PadBuddy/WatchApp.swift",
    "PadBuddy/TVApp.swift",
    "PadBuddy/TVProvisioningRequest.swift",
    "buddy-kit/Sources/BuddyAppKit/KeychainStore.swift"
]

/// Accessibility constants reviewed for credential storage: device-only, so a credential
/// cannot travel in an encrypted backup to another device.
let reviewedAccessibilityConstants = [
    "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly",
    "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"
]

let credentialAPIMarkers = [
    "SecItemAdd", "SecItemUpdate", "SecItemCopyMatching", "SecItemDelete", "kSecAttrAccessGroup"
]

/// The resolved `buddy-kit` checkout's sources.
///
/// The audit used to walk an in-repo `BuddyAppKit/` directory. That directory was a
/// stale copy the app never linked — the project resolves BuddyAppKit through a
/// remote package reference — so the gate was auditing a `KeychainStore` no user
/// runs while the shipping one went unchecked (#4822). This resolves the real one,
/// and fails rather than skipping if it cannot: an audit that quietly covers nothing
/// is worse than one that stops the build.
func buddyKitSourcesDirectory() -> URL {
    var candidates: [URL] = []
    if let override = ProcessInfo.processInfo.environment["BUDDY_KIT_SOURCES"] {
        candidates.append(URL(fileURLWithPath: override))
    }
    if let derived = ProcessInfo.processInfo.environment["CI_DERIVED_DATA_PATH"] {
        candidates.append(URL(fileURLWithPath: derived)
            .appendingPathComponent("SourcePackages/checkouts/buddy-kit/Sources"))
    }
    for relative in ["DerivedData/SourcePackages/checkouts/buddy-kit/Sources",
                     ".build/SourcePackages/checkouts/buddy-kit/Sources"] {
        candidates.append(root.appendingPathComponent(relative))
    }
    for candidate in candidates
        where FileManager.default.fileExists(atPath:
            candidate.appendingPathComponent("BuddyAppKit/KeychainStore.swift").path) {
        return candidate
    }
    fail("""
    Could not find the resolved buddy-kit sources. Resolve Swift package dependencies \
    before running this gate, or set BUDDY_KIT_SOURCES to the package's Sources directory. \
    Searched: \(candidates.map(\.path).joined(separator: ", "))
    """)
}

/// Each audited root, paired with the prefix its files are reported under. The prefix
/// is stable wherever the checkout happens to live, so `auditedStorePaths` does not
/// depend on a derived-data layout.
func shippingSourceRoots() -> [(prefix: String, directory: URL)] {
    [
        ("PadBuddy", root.appendingPathComponent("PadBuddy")),
        ("RecentPadsWidget", root.appendingPathComponent("RecentPadsWidget")),
        ("WatchApp", root.appendingPathComponent("WatchApp")),
        ("buddy-kit/Sources", buddyKitSourcesDirectory())
    ]
}

func shippingSwiftFiles() -> [(path: String, url: URL)] {
    var found: [(path: String, url: URL)] = []
    for (prefix, directory) in shippingSourceRoots() {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            fail("Could not enumerate \(prefix)")
        }

        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: directory.path + "/", with: "")
            // Build output and the package's own tests are not shipping sources.
            guard !relative.contains("/.build/"), !relative.contains("DerivedData"),
                  !relative.hasPrefix("Tests/"), !relative.contains("/Tests/") else { continue }

            found.append((prefix + "/" + relative, url))
        }
    }
    return found.sorted { $0.path < $1.path }
}

var discoveredStores: [String] = []
for (path, url) in shippingSwiftFiles() {
    guard let source = try? String(contentsOf: url, encoding: .utf8),
          credentialAPIMarkers.contains(where: source.contains) else { continue }

    discoveredStores.append(path)
    guard auditedStorePaths.contains(path) else {
        fail("\(path) performs Keychain item operations but is not in the audited store list; "
            + "review it against docs/keychain-policy.md and add it")
    }

    if source.contains("kSecAttrAccessGroup") {
        fail("\(path) sets an explicit access group; update docs/keychain-policy.md and provisioning first")
    }
    if source.contains("kSecAttrAccessible"),
       !reviewedAccessibilityConstants.contains(where: source.contains) {
        fail("\(path) sets a Keychain accessibility that is not one of the reviewed device-only values")
    }
}

let missingStores = auditedStorePaths.subtracting(discoveredStores)
guard missingStores.isEmpty else {
    // A listed store that no longer performs credential operations means the list is
    // stale, and a stale list is how an audit stops auditing anything.
    fail("audited store(s) no longer perform Keychain operations: \(missingStores.sorted().joined(separator: ", "))")
}

let sourcePolicies = [
    SourcePolicy(path: "PadBuddy/Accounts+Keychain.swift", required: ["KeychainStore(service: service"], patterns: []),
    SourcePolicy(path: "PadBuddy/WatchApp.swift", required: [
        "guard status == errSecItemNotFound else { return false }",
        "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"
    ], patterns: [privateEnumPrefix + #"WatchCredentialStore\b"#]),
    SourcePolicy(path: "PadBuddy/TVApp.swift", required: [
        "guard status == errSecItemNotFound else { return false }",
        "kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"
    ], patterns: [privateEnumPrefix + #"TVCredentialStore\b"#])
]

for policy in sourcePolicies {
    let sourceURL = root.appendingPathComponent(policy.path)
    guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
        fail("Could not read \(policy.path)")
    }

    for fragment in policy.required where !source.contains(fragment) {
        fail("\(policy.path) no longer satisfies the audited credential replacement and accessibility policy")
    }
    for pattern in policy.patterns where source.range(of: pattern, options: .regularExpression) == nil {
        fail("\(policy.path) no longer declares the audited private credential store")
    }
}

print("Keychain policy OK: \(entitlementFiles.count) entitlement files and "
    + "\(discoveredStores.count) discovered credential stores audited.")
