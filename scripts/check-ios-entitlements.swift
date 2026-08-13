#!/usr/bin/env swift

import Foundation

private let expectedGroup = "group.com.adamdangoor.padbuddy"
private let expectedKVS = "$(TeamIdentifierPrefix)com.adamdangoor.padbuddy"
private let projectPath = "PadBuddy.xcodeproj/project.pbxproj"
private let projectText = try String(contentsOfFile: projectPath, encoding: .utf8)

private struct ShippingConfiguration {
    let target: String
    let configuration: String
    let expectedPath: String
}

private let shippingConfigurations = [
    ShippingConfiguration(target: "PadBuddy", configuration: "Release", expectedPath: "PadBuddy-iOS.entitlements"),
    ShippingConfiguration(
        target: "PadBuddy",
        configuration: "AppStoreRelease",
        expectedPath: "PadBuddy-iOS.entitlements"
    ),
    ShippingConfiguration(
        target: "PadBuddy-AppStore",
        configuration: "Release",
        expectedPath: "PadBuddy-iOS.entitlements"
    ),
    ShippingConfiguration(
        target: "PadBuddy-AppStore",
        configuration: "AppStoreRelease",
        expectedPath: "PadBuddy-iOS.entitlements"
    ),
    ShippingConfiguration(
        target: "RecentPadsWidgetExtension",
        configuration: "Release",
        expectedPath: "RecentPadsWidgetExtension-iOS.entitlements"
    ),
    ShippingConfiguration(
        target: "RecentPadsWidgetExtension",
        configuration: "AppStoreRelease",
        expectedPath: "RecentPadsWidgetExtension-iOS.entitlements"
    )
]

private func dictionary(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw NSError(domain: "EntitlementCheck", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "\(path) is not a dictionary plist"])
    }

    return dictionary
}

private func selectedEntitlements(for shipping: ShippingConfiguration) throws -> String {
    let projectOnly = ProcessInfo.processInfo.environment["ENTITLEMENT_CHECK_PROJECT_ONLY"] == "1"
    guard !projectOnly, FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun") else {
        return try selectedEntitlementsFromProject(for: shipping)
    }

    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    process.arguments = [
        "xcodebuild", "-project", "PadBuddy.xcodeproj", "-target", shipping.target,
        "-configuration", shipping.configuration, "-sdk", "iphoneos", "-showBuildSettings"
    ]
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard let text = String(data: data, encoding: .utf8) else {
        throw NSError(domain: "EntitlementCheck", code: 9)
    }
    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "EntitlementCheck",
            code: 6,
            userInfo: [
                NSLocalizedDescriptionKey: "Could not resolve \(shipping.target) \(shipping.configuration): \(text)"
            ]
        )
    }

    let prefix = "    CODE_SIGN_ENTITLEMENTS = "
    guard let setting = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else {
        throw NSError(
            domain: "EntitlementCheck",
            code: 7,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "\(shipping.target) \(shipping.configuration) omits CODE_SIGN_ENTITLEMENTS"
            ]
        )
    }

    return String(setting.dropFirst(prefix.count))
}

private func objectBody(id: String) -> String? {
    let marker = "\t\t\(id) /*"
    guard let start = projectText.range(of: marker)?.lowerBound,
          let end = projectText.range(of: "\n\t\t};", range: start ..< projectText.endIndex)?.upperBound else {
        return nil
    }

    return String(projectText[start ..< end])
}

private func firstCapture(_ pattern: String, in text: String) -> String? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          match.numberOfRanges > 1,
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }

    return String(text[range])
}

private func selectedEntitlementsFromProject(for shipping: ShippingConfiguration) throws -> String {
    let configurationPattern = "(?ms)Build configuration list for PBXNativeTarget \""
        + NSRegularExpression.escapedPattern(for: shipping.target)
        + "\" \\*/ = \\{.*?buildConfigurations = \\(.*?([A-F0-9]+) /\\* "
        + NSRegularExpression.escapedPattern(for: shipping.configuration) + " \\*/"
    guard let configurationID = firstCapture(configurationPattern, in: projectText),
          let configuration = objectBody(id: configurationID),
          let path = firstCapture(
              #""CODE_SIGN_ENTITLEMENTS\[sdk=iphoneos\*\]" = "?([^";]+)"#,
              in: configuration
          ) else {
        throw NSError(
            domain: "EntitlementCheck",
            code: 11,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Could not resolve \(shipping.target) \(shipping.configuration) from \(projectPath)"
            ]
        )
    }

    return path
}

do {
    guard FileManager.default.fileExists(atPath: projectPath) else {
        throw NSError(
            domain: "EntitlementCheck",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Project file not found at \(projectPath)"]
        )
    }

    var paths = Set<String>()
    var sawApp = false
    var sawWidget = false
    for shipping in shippingConfigurations {
        let path = try selectedEntitlements(for: shipping)
        guard path == shipping.expectedPath else {
            let message = "\(shipping.target) \(shipping.configuration) selects \(path), "
                + "expected \(shipping.expectedPath)"
            throw NSError(
                domain: "EntitlementCheck",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        paths.insert(path)
    }

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
                throw NSError(
                    domain: "EntitlementCheck",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "\(path) is missing its team-scoped KVS entitlement"]
                )
            }
        }
    }

    guard sawApp, sawWidget else {
        throw NSError(
            domain: "EntitlementCheck",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Both iOS app and widget products must declare entitlements"]
        )
    }

    print("iOS entitlement parity passed for \(paths.count) build-setting file(s)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
