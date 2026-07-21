#!/usr/bin/env swift

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let entitlementFiles = [
    "coderpad/coderpad.entitlements",
    "coderpad-AppStore.entitlements",
    "RecentPadsWidgetExtension.entitlements",
    "RecentPadsWidgetExtension-AppStore.entitlements"
]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

for path in entitlementFiles {
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

let keychainSourcePath = "coderpad/Accounts+Keychain.swift"
let keychainSourceURL = root.appendingPathComponent(keychainSourcePath)
guard let source = try? String(contentsOf: keychainSourceURL, encoding: .utf8) else {
    fail("Could not read \(keychainSourcePath)")
}

guard source.contains("KeychainStore(service: service") else {
    fail("Local credential storage no longer uses the audited app-scoped KeychainStore")
}

guard !source.contains("kSecAttrAccessGroup") else {
    fail("Credential queries set an explicit access group; update docs/keychain-policy.md and provisioning first")
}

print("Keychain policy OK: app-private default group, no extension sharing, documented legacy accessibility.")
