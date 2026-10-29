import Foundation

extension ScreenResultRows {
    static func rows(_ source: ScreenQuestionWarning) -> [ScreenResultRow] {
        [
            value(String(localized: "Type"), source.type),
            value(String(localized: "Level"), source.level),
            value(String(localized: "Message"), source.message)
        ]
    }

    static func rows(_ source: ScreenAIReview) -> [ScreenResultRow] {
        [
            value(String(localized: "Rationale"), source.rationale),
            value(String(localized: "Recommended outcome"), source.recommendedOutcome),
            value(String(localized: "No recommendation reason"), source.noRecommendationReason)
        ]
    }

    static func rows(_ source: ScreenRubricCriterionResult) -> [ScreenResultRow] {
        [
            value(String(localized: "Label"), source.label),
            value(String(localized: "Description"), source.description),
            value(String(localized: "Skill"), source.skill),
            value(String(localized: "Outcome"), source.outcome),
            value(String(localized: "Maximum points"), source.maxPoints),
            value(String(localized: "Awarded points"), source.awardedPoints),
            value(String(localized: "Result message"), source.resultMessage),
            value(String(localized: "Result overridden by recruiter"), source.resultOverriddenByRecruiter),
            value(String(localized: "Review mode"), source.reviewMode),
            group(String(localized: "AI review"), source.aiReview, rows: rows)
        ]
    }

    static func rows(_ source: ScreenRubricResult) -> [ScreenResultRow] {
        [
            list(String(localized: "Criteria"), source.criteria, rows: rows)
        ]
    }

    static func rows(_ source: ScreenTestReportCaseResult) -> [ScreenResultRow] {
        [
            value(String(localized: "Key"), source.key),
            value(String(localized: "Label"), source.label),
            value(String(localized: "Skill"), source.skill),
            value(String(localized: "Outcome"), source.outcome),
            value(String(localized: "Output"), source.output),
            value(String(localized: "Test identifier"), source.testIdentifier),
            value(String(localized: "Maximum points"), source.maxPoints),
            value(String(localized: "Awarded points"), source.awardedPoints),
            value(String(localized: "Result overridden by recruiter"), source.resultOverriddenByRecruiter)
        ]
    }
}
