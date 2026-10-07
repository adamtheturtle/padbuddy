import SwiftUI

struct ScreenCampaignSettingsFields: View {
    @Binding var draft: ScreenCampaignSettingsDraft

    var body: some View {
        Section("Campaign Defaults") {
            Text("Default leaves each setting to the owning team's configuration.").font(.caption)
            Toggle("Override campaign languages", isOn: $draft.overrideLanguages)
            if draft.overrideLanguages {
                TextField("Language codes separated by commas", text: $draft.languages)
            }
            Picker("Timer", selection: $draft.timerMode) {
                Text("Default").tag(ScreenCampaignTimer.Mode?.none)
                Text("Per question").tag(ScreenCampaignTimer.Mode?.some(.perQuestion))
                Text("Global").tag(ScreenCampaignTimer.Mode?.some(.global))
                Text("Unlimited").tag(ScreenCampaignTimer.Mode?.some(.unlimited))
            }
            TextField("Global duration in minutes", text: $draft.timerDuration)
            TextField("Invitation expiration in days", text: $draft.expirationDays)
            Toggle("Override access period", isOn: $draft.overrideAccess)
            if draft.overrideAccess {
                DatePicker("Earliest start", selection: $draft.accessStart)
                DatePicker("Latest end", selection: $draft.accessEnd)
            }
        }
        Section("Candidate Experience") {
            ScreenSettingChoice(title: "Send simplified candidate report", value: $draft.simplifiedReport)
            ScreenSettingChoice(title: "Block copy and paste", value: $draft.copyPasteBlocked)
            ScreenSettingChoice(title: "Require full screen", value: $draft.fullScreen)
            ScreenSettingChoice(title: "Enable AI Assist", value: $draft.aiEnabled)
            Picker("Coding agents", selection: $draft.codingAgent) {
                Text("Default").tag(String?.none)
                Text("Disabled").tag(String?.some(""))
                Text("Claude Code").tag(String?.some("CLAUDE_CODE"))
                Text("Codex").tag(String?.some("CODEX"))
            }
        }
        Section("Follow-Up and Proctoring") {
            ScreenSettingChoice(title: "Enable follow-up questions", value: $draft.followUpEnabled)
            Picker("Follow-up answer format", selection: $draft.followUpFormat) {
                Text("Default").tag(ScreenCampaignFollowUpQuestions.AnswerFormat?.none)
                Text("Text").tag(ScreenCampaignFollowUpQuestions.AnswerFormat?.some(.text))
                Text("Video").tag(ScreenCampaignFollowUpQuestions.AnswerFormat?.some(.video))
                Text("Audio").tag(ScreenCampaignFollowUpQuestions.AnswerFormat?.some(.audio))
            }
            ScreenSettingChoice(title: "Webcam proctoring", value: $draft.webcamEnabled)
            ScreenSettingChoice(title: "Webcam AI analysis", value: $draft.webcamAI)
        }
    }
}

struct ScreenSettingChoice: View {
    let title: LocalizedStringKey
    @Binding var value: Bool?

    var body: some View {
        Picker(title, selection: $value) {
            Text("Default").tag(Bool?.none)
            Text("Enabled").tag(Bool?.some(true))
            Text("Disabled").tag(Bool?.some(false))
        }
    }
}

struct ScreenRandomQuestionFields: View {
    @Binding var draft: ScreenRandomQuestionDraft

    var body: some View {
        TextField("Domain", text: $draft.domain)
        TextField("Skills separated by commas", text: $draft.skills)
        Picker("Random question type", selection: $draft.questionType) {
            Text("Default").tag(ScreenRandomQuestionConfiguration.QuestionType?.none)
            Text("Quiz").tag(ScreenRandomQuestionConfiguration.QuestionType?.some(.quiz))
            Text("Code").tag(ScreenRandomQuestionConfiguration.QuestionType?.some(.code))
        }
        TextField("Target duration in minutes", text: $draft.duration)
        Picker("Target experience", selection: $draft.experience) {
            Text("Default").tag(ScreenRandomQuestionConfiguration.ExperienceLevel?.none)
            Text("Junior").tag(ScreenRandomQuestionConfiguration.ExperienceLevel?.some(.junior))
            Text("Senior").tag(ScreenRandomQuestionConfiguration.ExperienceLevel?.some(.senior))
            Text("Expert").tag(ScreenRandomQuestionConfiguration.ExperienceLevel?.some(.expert))
        }
        Picker("Question ID policy", selection: $draft.include) {
            Text("Include these IDs").tag(true)
            Text("Exclude these IDs").tag(false)
        }
        TextField("Question UUIDs (optional)", text: $draft.ids, axis: .vertical).lineLimit(2 ... 5)
        Text("An empty ID list lets the service select questions using the other criteria.").font(.caption)
    }
}
