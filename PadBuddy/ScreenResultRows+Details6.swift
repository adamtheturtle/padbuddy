import Foundation

extension ScreenResultRows {
    static func rows(_ source: ScreenMCQResultDetails) -> [ScreenResultRow] {
        [
            list(String(localized: "Choices"), source.choices, rows: rows),
            value(String(localized: "Selection mode"), source.selectionMode),
            value(String(localized: "Randomize choices"), source.randomizeChoices)
        ]
    }

    static func rows(_ source: ScreenDetailedQuestion) -> [ScreenResultRow] {
        [
            value(String(localized: "Version"), source.version),
            value(String(localized: "Domain"), source.domain),
            list(String(localized: "Warnings"), source.warnings, rows: rows),
            group(String(localized: "Evaluation"), source.evaluation, rows: rows),
            group(String(localized: "Answer"), source.answer, rows: rows),
            value(String(localized: "Maximum points"), source.maxPoints),
            value(String(localized: "Awarded points"), source.awardedPoints),
            value(String(localized: "Time limit (seconds)"), source.timeLimitSeconds),
            value(String(localized: "Time spent (seconds)"), source.timeSpentSeconds),
            value(String(localized: "First access (epoch milliseconds)"), source.firstAccessTime),
            value(String(localized: "Submission (epoch milliseconds)"), source.submissionTime),
            value(String(localized: "Last activity (epoch milliseconds)"), source.lastActivityTime),
            value(String(localized: "Answer status"), source.answerStatus),
            value(String(localized: "Grading status"), source.gradingStatus),
            value(String(localized: "Timed out"), source.timedOut),
            value(String(localized: "Result overridden by recruiter"), source.resultOverriddenByRecruiter),
            value(String(localized: "Marked as cheated by recruiter"), source.markedAsCheatedByRecruiter),
            value(
                String(localized: "Time outside environment (seconds)"),
                source.timeSpentOutsideEnvironmentSeconds
            ),
            value(String(localized: "Environment exit count"), source.environmentExitCount),
            group(String(localized: "Multiple choice options"), source.mcqDetails, rows: rows)
        ]
    }
}
