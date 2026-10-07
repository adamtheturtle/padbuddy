import Foundation

extension ScreenResultRows {
    static func rows(_ source: ScreenTestReportResult) -> [ScreenResultRow] {
        [
            list(String(localized: "Test cases"), source.testCases, rows: rows)
        ]
    }

    static func rows(_ source: ScreenValidationCodeCaseResult) -> [ScreenResultRow] {
        [
            value(String(localized: "Label"), source.label),
            value(String(localized: "Skill"), source.skill),
            value(String(localized: "Outcome"), source.outcome),
            value(String(localized: "Test identifier"), source.testIdentifier),
            value(String(localized: "Maximum points"), source.maxPoints),
            value(String(localized: "Awarded points"), source.awardedPoints),
            value(String(localized: "Result message"), source.resultMessage),
            value(String(localized: "Result overridden by recruiter"), source.resultOverriddenByRecruiter),
            value(String(localized: "Timed out"), source.timedOut)
        ]
    }

    static func rows(_ source: ScreenValidationCodeResult) -> [ScreenResultRow] {
        [
            list(String(localized: "Test cases"), source.testCases, rows: rows)
        ]
    }

    static func rows(_ source: ScreenInputOutputCaseResult) -> [ScreenResultRow] {
        [
            value(String(localized: "Label"), source.label),
            value(String(localized: "Skill"), source.skill),
            value(String(localized: "Outcome"), source.outcome),
            value(String(localized: "Maximum points"), source.maxPoints),
            value(String(localized: "Awarded points"), source.awardedPoints),
            value(String(localized: "Result message"), source.resultMessage),
            value(String(localized: "Result overridden by recruiter"), source.resultOverriddenByRecruiter),
            value(String(localized: "Timed out"), source.timedOut)
        ]
    }

    static func rows(_ source: ScreenInputOutputResult) -> [ScreenResultRow] {
        [
            list(String(localized: "Test cases"), source.testCases, rows: rows)
        ]
    }
}
