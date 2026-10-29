import Foundation

struct ScreenCampaignSettingsDraft: Equatable {
    var overrideLanguages = false
    var languages = ""
    var timerMode: ScreenCampaignTimer.Mode?
    var timerDuration = ""
    var expirationDays = ""
    var overrideAccess = false
    var accessStart = Date.now
    var accessEnd = Date.now.addingTimeInterval(86400)
    var simplifiedReport: Bool?
    var copyPasteBlocked: Bool?
    var followUpEnabled: Bool?
    var followUpFormat: ScreenCampaignFollowUpQuestions.AnswerFormat?
    var webcamEnabled: Bool?
    var webcamAI: Bool?
    var fullScreen: Bool?
    var aiEnabled: Bool?
    var codingAgent: String?

    private var hasOverrides: Bool {
        overrideLanguages || timerMode != nil || !timerDuration.isEmpty || !expirationDays.isEmpty || overrideAccess
            || simplifiedReport != nil || copyPasteBlocked != nil || followUpEnabled != nil || followUpFormat != nil
            || webcamEnabled != nil || webcamAI != nil || fullScreen != nil || aiEnabled != nil || codingAgent != nil
    }

    var validationMessage: String? {
        for value in [timerDuration, expirationDays] {
            if let message = ScreenCampaignDraft.positiveIntegerMessage(value) {
                return message
            }
        }
        if timerMode == .global, ScreenCampaignDraft.optional(timerDuration) == nil {
            return String(localized: "A global timer requires a duration in minutes.")
        }
        if ScreenCampaignDraft.optional(timerDuration) != nil, timerMode != .global {
            return String(localized: "Only a global timer can have a campaign duration.")
        }
        if overrideAccess, accessEnd < accessStart {
            return String(localized: "The access period must end after it starts.")
        }
        if overrideLanguages, parsedLanguages.isEmpty {
            return String(localized: "Enter at least one campaign language or use the team defaults.")
        }
        if followUpEnabled == false, followUpFormat != nil {
            return String(localized: "Clear the follow-up answer format when follow-up questions are disabled.")
        }
        if webcamEnabled == false, webcamAI == true {
            return String(localized: "Webcam AI analysis requires webcam proctoring.")
        }
        return nil
    }

    private var parsedLanguages: [String] {
        languages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var request: ScreenCampaignSettings? {
        guard hasOverrides else { return nil }

        return ScreenCampaignSettings(
            languages: overrideLanguages ? parsedLanguages : nil,
            timer: timerMode != nil || !timerDuration.isEmpty
                ? ScreenCampaignTimer(mode: timerMode,
                                      durationMinutes: ScreenCampaignDraft.optional(timerDuration)
                                          .flatMap(Int.init)) : nil,
            invitationExpirationDays: ScreenCampaignDraft.optional(expirationDays).flatMap(Int.init),
            accessPeriod: overrideAccess ? ScreenCampaignAccessPeriod(minStartTime: accessStart.ISO8601Format(),
                                                                      maxEndTime: accessEnd.ISO8601Format()) : nil,
            sendCandidateSimplifiedReport: simplifiedReport, copyPasteBlocked: copyPasteBlocked,
            followUpQuestions: followUpEnabled != nil || followUpFormat != nil
                ? ScreenCampaignFollowUpQuestions(enabled: followUpEnabled, answerFormat: followUpFormat) : nil,
            webcamProctoring: webcamEnabled != nil || webcamAI != nil
                ? ScreenCampaignWebcamProctoring(enabled: webcamEnabled, aiAnalysisEnabled: webcamAI) : nil,
            fullScreenRequired: fullScreen, aiAssistEnabled: aiEnabled, enabledCodingAgents: codingAgent
        )
    }
}
