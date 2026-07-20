#!/usr/bin/env swift

import Foundation

private let expectedGroup = "group.com.adamdangoor.padbuddy"
private let expectedKVS = "$(TeamIdentifierPrefix)com.adamdangoor.padbuddy"

private func dictionary(at path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw NSError(domain: "EntitlementCheck", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "\(path) is not a dictionary plist"])
    }

    return dictionary
}

do {
    let appPath = "coderpad-iOS.entitlements"
    let widgetPath = "RecentPadsWidgetExtension-iOS.entitlements"
    let app = try dictionary(at: appPath)
    let widget = try dictionary(at: widgetPath)
    let appGroups = app["com.apple.security.application-groups"] as? [String] ?? []
    let widgetGroups = widget["com.apple.security.application-groups"] as? [String] ?? []

    guard appGroups == [expectedGroup] else {
        throw NSError(domain: "EntitlementCheck", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "\(appPath) must use \(expectedGroup)"])
    }
    guard widgetGroups == appGroups else {
        throw NSError(domain: "EntitlementCheck", code: 3,
                      userInfo: [NSLocalizedDescriptionKey: "The iOS app and widget App Groups differ"])
    }
    guard app["com.apple.developer.ubiquity-kvstore-identifier"] as? String == expectedKVS else {
        throw NSError(domain: "EntitlementCheck", code: 4,
                      userInfo: [NSLocalizedDescriptionKey: "The iOS app is missing its team-scoped KVS entitlement"])
    }

    print("iOS entitlement parity passed")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
