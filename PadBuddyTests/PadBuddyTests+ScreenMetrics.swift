//
//  PadBuddyTests+ScreenMetrics.swift
//  PadBuddyTests
//

@testable import PadBuddy
import Foundation
import Testing

@Suite("Screen score formatting (#4681)")
struct ScreenScoreFormattingTests {
    @Test
    func `finite scores render as whole numbers`() {
        #expect(ScreenScoreFormatting.integerText(78.4) == "78")
        #expect(ScreenScoreFormatting.integerText(78.5) == "79")
        #expect(ScreenScoreFormatting.percentText(64) == "64%")
    }

    @Test
    func `non finite scores are unavailable instead of trapping`() {
        #expect(ScreenScoreFormatting.integerText(.nan) == nil)
        #expect(ScreenScoreFormatting.integerText(.infinity) == nil)
        #expect(ScreenScoreFormatting.integerText(-.infinity) == nil)
        #expect(ScreenScoreFormatting.percentText(.nan) == "—")
    }
}

@Suite("Screen report metrics")
struct ScreenReportMetricTests {
    @Test(arguments: [
        #"{"score":-0.1}"#,
        #"{"score":100.1}"#,
        #"{"comparative_score":-1}"#,
        #"{"comparative_score":101}"#
    ])
    func `report rejects percentages outside zero through one hundred`(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenReport.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: [0.0, 50.5, 100.0])
    func `report accepts percentage boundaries`(score: Double) throws {
        let json = #"{"score":\#(score),"comparative_score":\#(score)}"#
        let report = try JSONDecoder().decode(ScreenReport.self, from: Data(json.utf8))
        #expect(report.score == score)
        #expect(report.comparativeScore == score)
    }

    @Test
    func `invalid nested percentages drop only their malformed entries`() throws {
        let json = #"{"technologies":{"Valid":{"score":50},"Invalid":{"score":120}}}"#
        let report = try JSONDecoder().decode(ScreenReport.self, from: Data(json.utf8))

        #expect(report.technologies["Valid"]?.score == 50)
        #expect(report.technologies["Invalid"] == nil)
    }

    @Test
    func `breakdown keys are normalized bounded and collision safe`() throws {
        let longKey = "Long " + String(repeating: "x", count: 140)
        let object: [String: Any] = [
            "technologies": [
                " Java\n\t": ["score": 10],
                "Java": ["score": 20],
                "\u{200B}": ["score": 30],
                longKey: ["score": 40]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        let report = try JSONDecoder().decode(ScreenReport.self, from: data)

        #expect(report.technologies.keys.contains("Java"))
        #expect(report.technologies.keys.contains(where: { $0.count == 100 }))
        #expect(report.technologies.keys.allSatisfy { !$0.contains("\n") && !$0.contains("\t") })
        #expect(report.technologies.count == 2)
        #expect(report.omittedBreakdownEntries == 2)
    }

    @Test
    func `report collections and warning values are bounded`() throws {
        let technologies = Dictionary(uniqueKeysWithValues: (0 ..< 120).map {
            ("Technology \($0)", ["score": 50])
        })
        let warnings = [String(repeating: "x", count: 600)]
            + (0 ..< 120).map { " Warning \($0)\n" }
        let data = try JSONSerialization.data(withJSONObject: [
            "technologies": technologies,
            "warnings": warnings
        ])
        let report = try JSONDecoder().decode(ScreenReport.self, from: data)

        #expect(report.technologies.count == 100)
        #expect(report.omittedBreakdownEntries == 20)
        #expect(report.warnings.count == 100)
        #expect(report.warnings.allSatisfy { $0.count <= 500 && !$0.contains("\n") })
    }

    @Test(arguments: [
        #"{"duration":-1}"#,
        #"{"points":-1}"#,
        #"{"total_duration":-1}"#,
        #"{"total_points":-1}"#
    ])
    func `report rejects negative count and duration metrics`(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ScreenReport.self, from: Data(json.utf8))
        }
    }

    @Test
    func `negative nested points drop only their malformed entries`() throws {
        let json = #"{"technologies":{"Valid":{"points":0},"Invalid":{"total_points":-1}}}"#
        let report = try JSONDecoder().decode(ScreenReport.self, from: Data(json.utf8))

        #expect(report.technologies["Valid"]?.points == 0)
        #expect(report.technologies["Invalid"] == nil)
    }

    @Test
    func `present numeric report fields reject the wrong JSON type`() {
        let fields = ["duration", "points", "score", "total_duration", "total_points", "comparative_score"]
        for field in fields {
            let json = "{\"\(field)\":\"unknown\"}"
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(ScreenReport.self, from: Data(json.utf8))
            }
        }

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ScreenReport.self,
                from: Data(#"{"community_stats":[1,"unknown"]}"#.utf8)
            )
        }
    }
}
