#!/usr/bin/env swift

import Foundation

private struct Project: Decodable {
    let files: [ProjectFile]
    let targets: [Target]
}

private struct Target: Decodable {
    let name: String
    let buildPhases: [Membership]

    enum CodingKeys: String, CodingKey {
        case name
        case buildPhases = "build-phases"
    }
}

private struct Membership: Decodable {
    let name: String

    enum CodingKeys: String, CodingKey {
        case buildPhase = "build-phase"
        case kind
    }

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            name = string
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .buildPhase)
                ?? container.decode(String.self, forKey: .kind)
        }
    }
}

private struct ProjectFile: Decodable {
    let path: String?
    let kind: String?
    let children: [ProjectFile]?
    let targetMembership: [Membership]?
    let membershipExceptions: [MembershipException]?

    enum CodingKeys: String, CodingKey {
        case path, kind, children
        case targetMembership = "target-membership"
        case membershipExceptions = "membership-exceptions"
    }

    var descendants: [ProjectFile] {
        [self] + (children ?? []).flatMap(\.descendants)
    }
}

private struct MembershipException: Decodable {
    let exclusions: [String]?
}

private func require(_ condition: Bool, _ message: String) throws {
    guard condition else {
        throw NSError(domain: "PrivacyCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

do {
    let decoder = JSONDecoder()
    decoder.allowsJSON5 = true
    let project = try decoder.decode(Project.self, from: Data(contentsOf:
        URL(fileURLWithPath: CommandLine.arguments[1])))
    let files = project.files.flatMap(\.descendants)
    for (target, folder) in [
        ("PadBuddy", "PadBuddy"),
        ("PadBuddy-AppStore", "PadBuddy"),
        ("RecentPadsWidgetExtension", "RecentPadsWidget")
    ] {
        try require(files.contains {
            $0.kind == "folder" && $0.path == folder
                && ($0.targetMembership ?? []).contains { $0.name == target }
        }, "\(folder)/PrivacyInfo.xcprivacy is not attached to \(target)")
    }
    try require(!files.contains { file in
        (file.membershipExceptions ?? []).contains { exception in
            (exception.exclusions ?? []).contains { $0.hasSuffix("PrivacyInfo.xcprivacy") }
        }
    }, "a privacy manifest is excluded from a synchronized target")

    try require(project.targets.contains {
        $0.name == "PadBuddy Watch App" && $0.buildPhases.contains { $0.name == "resources" }
    }, "the PadBuddy Watch App target has no Resources build phase")
    try require(files.contains {
        $0.path == "WatchApp/PrivacyInfo.xcprivacy"
            && ($0.targetMembership ?? []).contains { $0.name == "PadBuddy Watch App/resources" }
    }, "WatchApp/PrivacyInfo.xcprivacy is not in the watch target's Resources phase")
    print("Project privacy membership passed.")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
