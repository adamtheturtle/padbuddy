import Foundation

struct CompanionPlatformPolicy: Equatable {
    enum Platform { case watchOS, tvOS }

    let browsableSections: [String]
    let allowsMutations: Bool
    let allowsSettings: Bool
    let unsupportedActionGuidance: String

    static func policy(for platform: Platform) -> Self {
        switch platform {
        case .watchOS, .tvOS:
            Self(
                browsableSections: ["pads", "questions"],
                allowsMutations: false,
                allowsSettings: false,
                unsupportedActionGuidance: "This companion is read only. "
                    + "Use PadBuddy on iPhone, iPad, or Mac to make changes."
            )
        }
    }
}
