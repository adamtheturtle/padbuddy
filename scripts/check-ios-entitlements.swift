#!/usr/bin/env swift

import Foundation

private let expectedGroup = "group.com.adamdangoor.padbuddy"
private let expectedKVS = "$(TeamIdentifierPrefix)com.adamdangoor.padbuddy"
private let projectPath = "coderpad.xcodeproj/project.pbxproj"

private func dictionary(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw NSError(domain: "EntitlementCheck", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "\(path) is not a dictionary plist"])
    }

    return dictionary
}

do {
    let project = try String(contentsOfFile: projectPath, encoding: .utf8)
    let pattern = #""CODE_SIGN_ENTITLEMENTS\[sdk=(?:iphoneos|iphonesimulator)\*\]" = "?([^";]+)"?;"#
    let regex = try NSRegularExpression(pattern: pattern)
    let range = NSRange(project.startIndex..., in: project)
    let paths = Set(regex.matches(in: project, range: range).compactMap { match -> String? in
        guard let pathRange = Range(match.range(at: 1), in: project) else { return nil }

        return String(project[pathRange])
    })

    guard !paths.isEmpty else {
        throw NSError(domain: "EntitlementCheck", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "No iOS entitlement build settings found in \(projectPath)"])
    }

    var sawApp = false
    var sawWidget = false
    for path in paths.sorted() {
        let entitlements = try dictionary(at: path)
        let groups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        guard groups == [expectedGroup] else {
            throw NSError(domain: "EntitlementCheck", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "\(path) must use \(expectedGroup)"])
        }

        if path.localizedCaseInsensitiveContains("widget") {
            sawWidget = true
        } else {
            sawApp = true
            guard entitlements["com.apple.developer.ubiquity-kvstore-identifier"] as? String == expectedKVS else {
                throw NSError(domain: "EntitlementCheck", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "\(path) is missing its team-scoped KVS entitlement"])
            }
        }
    }

    guard sawApp, sawWidget else {
        throw NSError(domain: "EntitlementCheck", code: 5,
                      userInfo: [NSLocalizedDescriptionKey: "Both iOS app and widget products must declare entitlements"])
    }

    print("iOS entitlement parity passed for \(paths.count) build-setting file(s)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
