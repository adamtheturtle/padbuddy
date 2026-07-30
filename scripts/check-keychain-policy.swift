#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let projectPath = "coderpad.xcodeproj/project.pbxproj"
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

let sourcePolicies: [(path: String, required: [String])] = [
    ("coderpad/Accounts+Keychain.swift", ["KeychainStore(service: service"])
]

for policy in sourcePolicies {
    let sourceURL = root.appendingPathComponent(policy.path)
    guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
        fail("Could not read \(policy.path)")
    }

    for fragment in policy.required where !source.contains(fragment) {
        fail("\(policy.path) no longer satisfies the audited credential replacement and accessibility policy")
    }
    if source.contains("kSecAttrAccessGroup") {
        fail("\(policy.path) sets an explicit access group; update docs/keychain-policy.md and provisioning first")
    }
}

print("Keychain policy OK: \(entitlementFiles.count) entitlement files and \(sourcePolicies.count) stores audited.")
