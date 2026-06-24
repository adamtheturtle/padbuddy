//
//  ScreenTestDetailView.swift
//  coderpad
//
//  The detail (third) column for a selected Screen test session (#435): status,
//  candidate, timing, tags, and — when the candidate has finished — the scored
//  report with a per-technology → per-skill breakdown, plus open/save of the report
//  PDF. Read-only. Refetches the single session to pick up the freshest report and
//  community stats.
//

#if os(macOS)
    import AppKit
#endif
import SwiftUI
import UniformTypeIdentifiers

struct ScreenTestDetailView: View {
    let client: ScreenClient
    let test: ScreenTestSession
    /// The freshest copy, refetched via `getTest` for community stats / latest report;
    /// falls back to the `test` passed from the list until the refetch lands.
    @State private var detail: ScreenTestSession?
    @State private var isFetchingReport = false
    @State private var reportError: String?
    // Optional report-export options (#443), mapped onto the Screen API's PDF query
    // params. All default off, so an untouched export keeps the server's defaults.
    @State private var exportAnonymized = false
    @State private var exportIncludeRank = false
    @State private var exportIncludeComparative = false

    /// The session to display: the refetched copy when available, else the list's.
    private var session: ScreenTestSession {
        detail ?? test
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                detailsSection
                if let report = session.report {
                    reportSection(report)
                } else {
                    noReport
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: test.id) { await refetch() }
        .alert("Couldn't open the report",
               isPresented: .init(get: { reportError != nil }, set: { if !$0 { reportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(candidate)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                ScreenStatusBadge(status: session.status)
                if let email = session.candidateEmail, !email.isEmpty, email != candidate {
                    MetaLabel(text: email, systemImage: "envelope")
                }
            }
        }
    }

    private var detailsSection: some View {
        DetailSection(title: "Details", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if let date = session.sendDate {
                    LabeledRow(label: "Invited", value: date.formatted(date: .long, time: .shortened))
                }
                if let date = session.startDate {
                    LabeledRow(label: "Started", value: date.formatted(date: .long, time: .shortened))
                }
                if let date = session.endDate {
                    LabeledRow(label: "Completed", value: date.formatted(date: .long, time: .shortened))
                }
                if let date = session.lastActivityDate {
                    LabeledRow(label: "Last activity", value: date.formatted(date: .long, time: .shortened))
                }
                if !session.tags.isEmpty {
                    LabeledRow(label: "Tags", value: session.tags.joined(separator: ", "))
                }
            }
        }
    }

    private func reportSection(_ report: ScreenReport) -> some View {
        DetailSection(title: "Report", systemImage: "chart.bar.doc.horizontal") {
            reportPDFButton
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if let score = report.score {
                        LabeledRow(label: "Score", value: scoreText(score, outOf: report.totalPoints))
                    }
                    if let points = report.points {
                        LabeledRow(label: "Points", value: pointsText(points, outOf: report.totalPoints))
                    }
                    if let duration = report.totalDuration ?? report.duration {
                        LabeledRow(label: "Duration", value: durationText(duration))
                    }
                    if let comparative = report.comparativeScore {
                        LabeledRow(label: "vs. community",
                                   value: "\(Int(comparative.rounded()))%")
                    }
                }
                if !report.warnings.isEmpty {
                    warnings(report.warnings)
                }
                if !report.technologies.isEmpty {
                    technologyBreakdown(report.technologies)
                }
            }
        }
    }

    private func warnings(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Proctoring warnings", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            ForEach(warnings, id: \.self) { warning in
                Text("• \(warning)").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func technologyBreakdown(_ technologies: [String: ScreenTechnologyResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By technology")
                .font(.callout.weight(.medium))
            ForEach(technologies.sorted(by: { $0.key < $1.key }), id: \.key) { name, result in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name).font(.callout.weight(.medium))
                        Spacer(minLength: 0)
                        if let score = result.score {
                            Text(scoreText(score, outOf: result.totalPoints))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(result.skills.sorted(by: { $0.key < $1.key }), id: \.key) { skill, value in
                        HStack {
                            Text(skill).font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if let score = value.score {
                                Text(scoreText(score, outOf: value.totalPoints))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 12)
                    }
                }
            }
        }
    }

    private var reportPDFButton: some View {
        HStack(spacing: 8) {
            if isFetchingReport {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await openReport(save: false) }
            } label: {
                Label("Open PDF", systemImage: "doc.richtext")
            }
            .disabled(isFetchingReport)
            Button {
                Task { await openReport(save: true) }
            } label: {
                Label("Save PDF", systemImage: "square.and.arrow.down")
            }
            .disabled(isFetchingReport)
            Menu {
                Toggle("Anonymized", isOn: $exportAnonymized)
                Toggle("Include rank", isOn: $exportIncludeRank)
                Toggle("Include comparative score", isOn: $exportIncludeComparative)
            } label: {
                Label("Report Options", systemImage: "slider.horizontal.3")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose what the exported PDF report includes.")
        }
        .help("Fetch the candidate's report as a PDF.")
    }

    private var noReport: some View {
        ContentUnavailableView {
            Label("No report yet", systemImage: "clock")
        } description: {
            Text("The scored report appears once the candidate completes the test.")
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var candidate: String {
        if let name = session.candidateName, !name.isEmpty { return name }
        if let email = session.candidateEmail, !email.isEmpty { return email }
        return String(localized: "Unknown candidate")
    }

    // MARK: Formatting

    private func scoreText(_ score: Double, outOf total: Int?) -> String {
        if let total, total > 0 { return "\(Int(score.rounded()))/\(total)" }
        return "\(Int(score.rounded()))"
    }

    private func pointsText(_ points: Int, outOf total: Int?) -> String {
        if let total, total > 0 { return "\(points)/\(total)" }
        return "\(points)"
    }

    private func durationText(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    // MARK: Data

    private func refetch() async {
        // Non-fatal: the list already gave us a usable session, so a failed refetch
        // just leaves the existing data in place.
        detail = try? await client.getTest(id: test.id, withCommunityStats: true)
    }

    /// Fetches the report PDF, then either opens it (temp file) or offers a save panel.
    private func openReport(save: Bool) async {
        isFetchingReport = true
        defer { isFetchingReport = false }
        do {
            let data = try await client.testReport(
                id: test.id,
                anonymous: exportAnonymized ? true : nil,
                includeRank: exportIncludeRank ? true : nil,
                includeComparativeScore: exportIncludeComparative ? true : nil
            )
            if save {
                saveReport(data)
            } else {
                #if os(macOS)
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("ScreenReport-\(test.id).pdf")
                    try data.write(to: url)
                    NSWorkspace.shared.open(url)
                #else
                    // Opening the PDF (a document preview / share sheet) can be added
                    // later on iPad; for now this is a no-op so the button stays inert.
                #endif
            }
        } catch {
            reportError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Offers a save panel (sandbox-safe: the user grants write access to the chosen
    /// location) and writes the fetched PDF there.
    private func saveReport(_ data: Data) {
        #if os(macOS)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "ScreenReport-\(test.id).pdf"
            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                try data.write(to: url)
            } catch {
                reportError = error.localizedDescription
            }
        #else
            // Saving the PDF (a document picker / share sheet) can be added later on
            // iPad; for now this is a no-op so the button stays inert.
            _ = data
        #endif
    }
}

#Preview("Completed report") {
    ScreenTestDetailView(
        client: .live(apiKey: "preview"),
        test: ScreenTestSession(
            id: 1, status: "completed",
            report: ScreenReport(
                score: 78, points: 78, duration: 3120, warnings: ["Left full screen twice"],
                totalPoints: 100, comparativeScore: 64
            ),
            candidateName: "Ada Lovelace", candidateEmail: "ada@example.com",
            tags: ["referral"], sendTime: 1_699_000_000_000, endTime: 1_700_000_000_000
        )
    )
    .frame(width: 460, height: 600)
}

#Preview("Not completed") {
    ScreenTestDetailView(
        client: .live(apiKey: "preview"),
        test: ScreenTestSession(
            id: 2, status: "waiting",
            candidateName: "Alan Turing", sendTime: 1_700_000_000_000
        )
    )
    .frame(width: 460, height: 600)
}
