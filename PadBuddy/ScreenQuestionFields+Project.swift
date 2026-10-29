import SwiftUI

extension ScreenQuestionFields {
    static func fields(_ value: Binding<ScreenEnvironmentInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.text(String(localized: "Version"), value: value.version)
            Self.text(String(localized: "Environment ID"), value: value.environmentID)
        }
    }

    static func fields(_ value: Binding<ScreenDatabaseEngineInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.text(String(localized: "Version"), value: value.version)
            Self.text(String(localized: "Database engine ID"), value: value.engineID)
        }
    }

    static func fields(_ value: Binding<ScreenProjectResourceInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.text(String(localized: "Version"), value: value.version)
            Self.text(String(localized: "Resource ID"), value: value.resourceID)
        }
    }

    static func fields(_ value: Binding<ScreenProjectInput>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Self.included(
                String(localized: "Environment"),
                value: value.environment,
                make: ScreenEnvironmentInput()
            ) { fields($0) }
            Self
                .array(String(localized: "Resources"), value: value.resources, make: ScreenProjectResourceInput(
                )) {
                    fields($0)
                }
            Self.text(String(localized: "AI assistance instructions"), value: value.aiAssistAdditionalInstructions)
            Self.boolean(String(localized: "Allow AI assistance"), value: value.aiAssistAllowed)
        }
    }
}
