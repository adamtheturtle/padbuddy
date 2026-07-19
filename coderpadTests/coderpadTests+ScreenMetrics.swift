//
//  coderpadTests+ScreenMetrics.swift
//  coderpadTests
//

@testable import CoderPad
import Foundation
import Testing

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
}
