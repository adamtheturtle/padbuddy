#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let projectPath = "PadBuddy.xcodeproj/project.pbxproj"
let projectURL = root.appendingPathComponent(projectPath)
guard let project = try? String(contentsOf: projectURL, encoding: .utf8) else {
    fail("Could not read \(projectPath)")
}

let entitlementPattern = #"CODE_SIGN_ENTITLEMENTS(?:\[[^\]]+\])? = "?([^";]+)"?;"#
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
    "BuddyAppKit/Sources/BuddyAppKit/KeychainStore.swift"
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

let shippingSourceRoots = ["PadBuddy", "RecentPadsWidget", "WatchApp", "BuddyAppKit/Sources"]

func shippingSwiftFiles() -> [String] {
    var found: [String] = []
    for rootName in shippingSourceRoots {
        let directory = root.appendingPathComponent(rootName)
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            fail("Could not enumerate \(rootName)")
        }

        for case let url as URL in walker where url.pathExtension == "swift" {
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            // Build output and package checkouts are not shipping sources.
            guard !relative.contains("/.build/"), !relative.contains("DerivedData"),
                  !relative.contains("/Tests/") else { continue }

            found.append(relative)
        }
    }
    return found.sorted()
}

var discoveredStores: [String] = []
for path in shippingSwiftFiles() {
    guard let source = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8),
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
