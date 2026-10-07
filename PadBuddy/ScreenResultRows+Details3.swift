import Foundation

extension ScreenResultRows {
    static func rows(_ source: ScreenSQLComparisonResult) -> [ScreenResultRow] {
        [
            value(String(localized: "Outcome"), source.outcome),
            value(String(localized: "Maximum points"), source.maxPoints),
            value(String(localized: "Awarded points"), source.awardedPoints),
            value(String(localized: "Result message"), source.resultMessage),
            value(String(localized: "Result overridden by recruiter"), source.resultOverriddenByRecruiter),
            value(String(localized: "Timed out"), source.timedOut)
        ]
    }

    static func rows(_ source: ScreenAcceptedAnswer) -> [ScreenResultRow] {
        [
            value(String(localized: "Value"), source.value),
            value(String(localized: "Match type"), source.matchType)
        ]
    }

    static func rows(_ source: ScreenTextAnswerMatchingResult) -> [ScreenResultRow] {
        [
            list(String(localized: "Accepted answers"), source.acceptedAnswers, rows: rows)
        ]
    }

    static func rows(_ source: ScreenChoiceSelectionResult) -> [ScreenResultRow] {
        [
            values(String(localized: "Correct choice indexes (starting at 0)"), source.correctChoiceIndexes)
        ]
    }

    static func rows(_ source: ScreenQuestionEvaluation) -> [ScreenResultRow] {
        [
            group(String(localized: "Rubric"), source.rubric, rows: rows),
            group(String(localized: "Project test results"), source.testReport, rows: rows),
            group(String(localized: "Validation results"), source.validationCode, rows: rows),
            group(String(localized: "Input and output results"), source.inputOutput, rows: rows),
            group(String(localized: "SQL comparison results"), source.sqlQueryResultComparison, rows: rows),
            group(String(localized: "Accepted answers"), source.textAnswerMatching, rows: rows),
            group(String(localized: "Correct choices"), source.choiceSelection, rows: rows)
        ]
    }
}
