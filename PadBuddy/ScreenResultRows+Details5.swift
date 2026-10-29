import Foundation

extension ScreenResultRows {
    static func rows(_ source: ScreenProjectAnswer) -> [ScreenResultRow] {
        [
            value(String(localized: "Download URL"), source.downloadURL),
            value(String(localized: "AI Assist conversation count"), source.aiAssistConversationCount)
        ]
    }

    static func rows(_ source: ScreenRecording) -> [ScreenResultRow] {
        [
            value(String(localized: "Recording ID"), source.id),
            value(String(localized: "Recording URL"), source.url),
            value(String(localized: "Transcript URL"), source.transcriptURL),
            value(String(localized: "Duration (seconds)"), source.durationSeconds)
        ]
    }

    static func rows(_ source: ScreenVideoAnswer) -> [ScreenResultRow] {
        [
            list(String(localized: "Recordings"), source.recordings, rows: rows),
            value(String(localized: "Recording availability"), source.recordingAvailability),
            value(String(localized: "Candidate comment"), source.candidateComment)
        ]
    }

    static func rows(_ source: ScreenQuestionAnswer) -> [ScreenResultRow] {
        let entries: [ScreenResultRow?] = [
            source.codeAnswer.map { .group(String(localized: "Code submission"), rows($0)) },
            source.gameAnswer.map { .group(String(localized: "Game submission"), rows($0)) },
            source.mcqAnswer.map { .group(String(localized: "Selected choices"), rows($0)) },
            source.textAnswer.map { .group(String(localized: "Text submission"), rows($0)) },
            source.fileUploadAnswer.map { .group(String(localized: "Submitted file"), rows($0)) },
            source.projectAnswer.map { .group(String(localized: "Submitted project"), rows($0)) },
            source.videoAnswer.map { .group(String(localized: "Candidate recordings"), rows($0)) }
        ]
        return entries.compactMap(\.self)
    }

    static func rows(_ source: ScreenMCQChoice) -> [ScreenResultRow] {
        [
            value(String(localized: "Label"), source.label)
        ]
    }
}
