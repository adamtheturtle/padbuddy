import Foundation

extension ScreenResultRows {
    static func rows(_ source: ScreenCodeAnswer) -> [ScreenResultRow] {
        [
            value(String(localized: "Code"), source.code),
            value(String(localized: "Programming language"), source.programmingLanguageID)
        ]
    }

    static func rows(_ source: ScreenGameAnswer) -> [ScreenResultRow] {
        [
            value(String(localized: "Code"), source.code),
            value(String(localized: "Programming language"), source.programmingLanguageID)
        ]
    }

    static func rows(_ source: ScreenMCQAnswer) -> [ScreenResultRow] {
        [
            values(String(localized: "Selected choice indexes (starting at 0)"), source.selectedChoiceIndexes)
        ]
    }

    static func rows(_ source: ScreenTextAnswer) -> [ScreenResultRow] {
        [
            value(String(localized: "Text"), source.text)
        ]
    }

    static func rows(_ source: ScreenFileUploadAnswer) -> [ScreenResultRow] {
        [
            value(String(localized: "Filename"), source.filename),
            value(String(localized: "Download URL"), source.downloadURL),
            value(String(localized: "Candidate comment"), source.candidateComment)
        ]
    }
}
