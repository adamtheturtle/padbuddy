import SwiftUI

struct ScreenCampaignDefinitionSettings: View {
    let settings: ScreenCampaignSettings

    var body: some View {
        Section("Campaign Defaults") {
            value("Languages", settings.languages?.joined(separator: ", "))
            if let mode = settings.timer?.mode {
                LabeledContent("Timer") { Text(timerLabel(mode)) }
            }
            value("Global duration in minutes", settings.timer?.durationMinutes.map(String.init))
            value("Invitation expiration in days", settings.invitationExpirationDays.map(String.init))
            value("Earliest start", settings.accessPeriod?.minStartTime)
            value("Latest end", settings.accessPeriod?.maxEndTime)
        }
        Section("Candidate Experience") {
            flag("Send simplified candidate report", settings.sendCandidateSimplifiedReport)
            flag("Block copy and paste", settings.copyPasteBlocked)
            flag("Require full screen", settings.fullScreenRequired)
            flag("Enable AI Assist", settings.aiAssistEnabled)
            value("Coding agents", settings.enabledCodingAgents)
        }
        Section("Follow-Up and Proctoring") {
            flag("Enable follow-up questions", settings.followUpQuestions?.enabled)
            if let format = settings.followUpQuestions?.answerFormat {
                LabeledContent("Follow-up answer format") { Text(answerLabel(format)) }
            }
            flag("Webcam proctoring", settings.webcamProctoring?.enabled)
            flag("Webcam AI analysis", settings.webcamProctoring?.aiAnalysisEnabled)
        }
    }

    private func timerLabel(_ mode: ScreenCampaignTimer.Mode) -> LocalizedStringKey {
        switch mode {
        case .perQuestion: "Per question"
        case .global: "Global"
        case .unlimited: "Unlimited"
        }
    }

    private func answerLabel(_ format: ScreenCampaignFollowUpQuestions.AnswerFormat) -> LocalizedStringKey {
        switch format {
        case .text: "Text"
        case .video: "Video"
        case .audio: "Audio"
        }
    }

    @ViewBuilder
    private func flag(_ title: LocalizedStringKey, _ enabled: Bool?) -> some View {
        if let enabled {
            LabeledContent(title) { Text(enabled ? "Enabled" : "Disabled") }
        }
    }

    @ViewBuilder
    private func value(_ title: LocalizedStringKey, _ text: String?) -> some View {
        if let text {
            LabeledContent(title) {
                if text.isEmpty {
                    Text("None")
                } else {
                    Text(verbatim: text).textSelection(.enabled)
                }
            }
        }
    }
}

struct ScreenCampaignRandomSelectionDetails: View {
    let configuration: ScreenRandomQuestionConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let domain = configuration.domain {
                LabeledContent("Domain", value: domain)
            }
            if let skills = configuration.skills {
                LabeledContent("Skills", value: skills.joined(separator: ", "))
            }
            if let type = configuration.questionType {
                LabeledContent("Random question type", value: type.rawValue)
            }
            if let duration = configuration.targetDurationMinutes {
                LabeledContent("Target duration in minutes", value: String(duration))
            }
            if let experience = configuration.targetExperienceLevel {
                LabeledContent("Target experience", value: experience.rawValue)
            }
            if let ids = configuration.includedQuestionIDs {
                questionIDs("Include these IDs", ids)
            }
            if let ids = configuration.excludedQuestionIDs {
                questionIDs("Exclude these IDs", ids)
            }
        }
    }

    private func questionIDs(_ title: LocalizedStringKey, _ ids: [UUID]) -> some View {
        LabeledContent(title) {
            Text(verbatim: ids.map(\.uuidString).joined(separator: ", ")).font(.caption).textSelection(.enabled)
        }
    }
}
