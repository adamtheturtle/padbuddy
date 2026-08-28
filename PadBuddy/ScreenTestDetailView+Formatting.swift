//
//  ScreenTestDetailView+Formatting.swift
//  coderpad
//
//  Score/points/duration formatting for the Screen test detail (#435), plus the
//  iPad report-export document (#808) and the detail previews. Split from
//  ScreenTestDetailView.swift to keep it within the lint length budget.
//

import SwiftUI
import UniformTypeIdentifiers

extension ScreenTestDetailView {
    /// `score` is an API percentage (0-100), not raw points, so it renders with a
    /// percent sign rather than over the raw `totalPoints` denominator (#995).
    func scoreText(_ score: Double) -> String {
        ScreenScoreFormatting.percentText(score)
    }

    func pointsText(_ points: Int, outOf total: Int?) -> String {
        if let total, total > 0 {
            return "\(points)/\(total)"
        }
        return "\(points)"
    }

    func durationText(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

#if !os(macOS)
    /// A fetched Screen report PDF staged for the iPad's `.fileExporter` (#808).
    struct ScreenReportExportDocument: FileDocument {
        static var readableContentTypes: [UTType] {
            []
        }

        static var writableContentTypes: [UTType] {
            [.pdf]
        }

        private let data: Data

        init(data: Data) {
            self.data = data
        }

        init(configuration _: ReadConfiguration) throws {
            throw CocoaError(.fileReadCorruptFile)
        }

        func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
#endif

#Preview("Completed report") {
    // Build the sample session in its own statements to keep the view
    // expression under the 250ms type-check budget (warnings-as-errors).
    // The memberwise inits validate their ids and scores, so the samples are optional.
    let report = try? ScreenReport(
        score: 78, points: 78, duration: 3120, warnings: ["Left full screen twice"],
        totalPoints: 100, comparativeScore: 64
    )
    let session = try? ScreenTestSession(
        id: 1, status: "completed",
        report: report,
        candidateName: "Ada Lovelace", candidateEmail: "ada@example.com",
        tags: ["referral"], sendTime: 1_699_000_000_000, endTime: 1_700_000_000_000
    )
    if let session {
        ScreenTestDetailView(client: .live(apiKey: "preview"), test: session)
            .frame(width: 460, height: 600)
    }
}

#Preview("Not completed") {
    // The memberwise init validates its id, so the sample is optional.
    let session = try? ScreenTestSession(
        id: 2, status: "waiting",
        candidateName: "Alan Turing", sendTime: 1_700_000_000_000
    )
    if let session {
        ScreenTestDetailView(client: .live(apiKey: "preview"), test: session)
            .frame(width: 460, height: 600)
    }
}
