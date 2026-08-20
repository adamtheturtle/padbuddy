//
//  ScreenScoreFormatting.swift
//  PadBuddy
//
//  Safe display helpers for remote Screen percentage metrics. `Int(score.rounded())`
//  traps on NaN/infinity, so every list/copy/detail path goes through this gate (#4681).
//

import Foundation

nonisolated enum ScreenScoreFormatting {
    /// Whole-number percentage text for a remote score, or `nil` when the value is
    /// non-finite and cannot be converted to `Int` safely.
    static func integerText(_ score: Double) -> String? {
        guard score.isFinite else { return nil }

        return String(Int(score.rounded()))
    }

    /// Whole-number percentage with a trailing `%`, or a localized unavailable mark.
    static func percentText(_ score: Double) -> String {
        guard let text = integerText(score) else { return String(localized: "—") }

        return "\(text)%"
    }
}
