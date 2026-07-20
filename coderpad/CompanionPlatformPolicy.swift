import Foundation

struct CompanionPlatformPolicy: Equatable {
    enum Platform { case watchOS, tvOS }

    let browsableSections: [String]
    let allowsMutations: Bool
    let allowsSettings: Bool

    static func policy(for platform: Platform) -> Self {
        switch platform {
        case .watchOS, .tvOS:
            Self(browsableSections: ["pads", "questions"], allowsMutations: false, allowsSettings: false)
        }
    }
}
