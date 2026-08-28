//
//  PadBuddyTests+CompanionResilience.swift
//  PadBuddyTests
//
//  The tvOS language-label fold (#4821) lives behind `#if os(tvOS)` in TVApp.swift,
//  which is not built into this target, so it has no coverage here.
//
import Foundation
@testable import PadBuddy
import Testing

@Suite("Bulk delete summaries")
struct BulkDeleteSummaryTests {
    /// Titles are remote content interpolated straight into an alert. Three
    /// untruncated ones can push it past anything it can lay out, and a newline or
    /// bidi override could restructure the message (#4820).
    @Test func `a long title is truncated`() {
        let long = String(repeating: "t", count: 500)

        let summary = BulkDeleteUndo.summary(of: [long])

        #expect(summary.count == BulkDeleteUndo.maxTitleLength + 1)
        #expect(summary.hasSuffix("…"))
    }

    @Test func `newlines and format scalars cannot restructure the message`() {
        let summary = BulkDeleteUndo.summary(of: ["First\nSecond\u{202E}Third"])

        #expect(!summary.contains("\n"))
        #expect(!summary.unicodeScalars.contains { $0.properties.generalCategory == .format })
        #expect(summary == "First SecondThird")
    }

    @Test func `a blank title reads as untitled`() {
        #expect(BulkDeleteUndo.summary(of: ["   \n  "]) == String(localized: "Untitled"))
        #expect(BulkDeleteUndo.summary(of: ["\u{202E}"]) == String(localized: "Untitled"))
    }

    @Test func `ordinary titles are listed and the remainder counted`() {
        let summary = BulkDeleteUndo.summary(of: ["A", "B", "C", "D", "E"], limit: 3)

        #expect(summary.hasPrefix("A, B, C"))
        #expect(summary.contains("2"))
    }
}
