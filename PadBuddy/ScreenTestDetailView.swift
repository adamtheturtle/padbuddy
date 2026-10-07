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
#else
    import QuickLook
#endif
import SwiftUI
import UniformTypeIdentifiers

struct ScreenTestDetailView: View {
    let client: ScreenClient
    let test: ScreenTestSession
    /// The freshest copy, refetched via `getTest` for community stats / latest report;
    /// falls back to the `test` passed from the list until the refetch lands.
    @State var detail: ScreenTestSession?
    /// Which (session, client) produced `detail`: numeric session ids collide across
    /// Screen accounts, so an id-only identity let a reused view show or refetch the
    /// wrong account's report (#1860).
    @State var detailFor: FetchIdentity?
    /// Monotonic id of the newest `refetch()`: without it, a slow response for a
    /// previous selection could land after a newer one and overwrite `detail` (#1861).
    @State var fetchGeneration = 0
    /// A failed refetch (#921): the list's copy stays on screen, but flagged stale
    /// rather than silently posing as the session's current state.
    @State var refreshError: String?
    @State var isFetchingReport = false
    @State var reportError: String?
    // Optional report-export options (#443), mapped onto the Screen API's PDF query
    // params. All default off, so an untouched export keeps the server's defaults.
    @State var exportAnonymized = false
    @State var exportIncludeRank = false
    @State var exportIncludeComparative = false
    #if !os(macOS)
        /// The staged PDF Quick Look is previewing after Open PDF (#808).
        @State var reportPreviewURL: URL?
        /// The fetched PDF staged for the save-file exporter (#808).
        @State var pendingReportExport: ScreenReportExportDocument?
    #endif

    /// Session identity for fetches: the id plus the client's account coordinates,
    /// because per-account session ids collide (#1860).
    struct FetchIdentity: Hashable {
        let testID: Int
        let apiKey: String
        let baseURL: URL
    }

    var fetchIdentity: FetchIdentity {
        FetchIdentity(testID: test.id, apiKey: client.apiKey, baseURL: client.baseURL)
    }

    /// The session to display: the refetched copy when it belongs to the current
    /// (session, client) identity, else the list's.
    var session: ScreenTestSession {
        (detailFor == fetchIdentity ? detail : nil) ?? test
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let refreshError {
                    StaleRefreshBanner(message: refreshError) { Task { await refetch() } }
                }
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
        .task(id: fetchIdentity) { await refetch() }
        .onChange(of: fetchIdentity) { _, _ in
            // A Quick Look preview or staged export for the previous candidate must not
            // remain presented under the newly selected session (#4680).
            clearReportPresentationState()
        }
        .alert("Could not open the report",
               isPresented: .init(get: { reportError != nil }, set: {
                   if !$0 {
                       reportError = nil
                   }
               })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportError ?? "")
        }
        #if !os(macOS)
        .quickLookPreview($reportPreviewURL)
        .fileExporter(
            isPresented: .init(get: { pendingReportExport != nil },
                               set: {
                                   if !$0 {
                                       pendingReportExport = nil
                                   }
                               }),
            document: pendingReportExport,
            contentType: .pdf,
            defaultFilename: "ScreenReport-\(test.id).pdf"
        ) { result in
            if case let .failure(error) = result {
                reportError = error.localizedDescription
            }
            pendingReportExport = nil
        }
        #endif
    }

    func clearReportPresentationState() {
        reportError = nil
        isFetchingReport = false
        #if !os(macOS)
            if let reportPreviewURL {
                ScreenReportFiles.scheduleRemoval(of: reportPreviewURL)
            }
            reportPreviewURL = nil
            pendingReportExport = nil
        #endif
    }

    var header: some View {
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

    var detailsSection: some View {
        DetailSection(title: "Details", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if let date = session.sendDate {
                    LabeledRow(label: "Invited", value: date.formatted(SharedDateStyles.longDateAndTime))
                }
                if let date = session.startDate {
                    LabeledRow(label: "Started", value: date.formatted(SharedDateStyles.longDateAndTime))
                }
                if let date = session.endDate {
                    // "Completed" only when the session actually completed; an aborted or
                    // cancelled session also carries an end_time, so label those ends
                    // neutrally rather than contradicting the status badge (#1012).
                    LabeledRow(label: session.status == "completed" ? "Completed" : "Ended",
                               value: date.formatted(SharedDateStyles.longDateAndTime))
                }
                if let date = session.lastActivityDate {
                    LabeledRow(label: "Last activity", value: date.formatted(SharedDateStyles.longDateAndTime))
                }
                if !session.tags.isEmpty {
                    LabeledRow(label: "Tags", value: session.tags.joined(separator: ", "))
                }
            }
        }
    }

    func reportSection(_ report: ScreenReport) -> some View {
        DetailSection(title: "Report", systemImage: "chart.bar.doc.horizontal") {
            reportPDFButton
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if let score = report.score {
                        LabeledRow(label: "Score", value: scoreText(score))
                    }
                    if let points = report.points {
                        LabeledRow(label: "Points", value: pointsText(points, outOf: report.totalPoints))
                    }
                    if let duration = report.totalDuration ?? report.duration {
                        LabeledRow(label: "Duration", value: durationText(duration))
                    }
                    if let comparative = report.comparativeScore {
                        LabeledRow(label: "vs. community",
                                   value: ScreenScoreFormatting.percentText(comparative))
                    }
                }
                if !report.warnings.isEmpty {
                    warnings(report.warnings)
                }
                if report.omittedWarningCount > 0 {
                    Label("Some proctoring warnings could not be displayed.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                if report.omittedBreakdownEntries > 0 {
                    Label(
                        "Some technology or skill results could not be displayed.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.orange)
                }
                if !report.technologies.isEmpty {
                    technologyBreakdown(report.technologies)
                }
            }
        }
    }

    func warnings(_ warnings: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Proctoring warnings", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(.orange)
            ForEach(Self.warningRows(warnings)) { warning in
                Text("• \(warning.text)").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    nonisolated static func warningRows(_ warnings: [String]) -> [ScreenWarningRow] {
        warnings.enumerated().map { ScreenWarningRow(id: $0.offset, text: $0.element) }
    }

    var reportPDFButton: some View {
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
            .disabled(isFetchingReport)
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Choose what the exported PDF report includes.")
        }
        .help("Fetch the candidate's report as a PDF.")
    }

    var noReport: some View {
        ContentUnavailableView {
            Label("No report yet", systemImage: "clock")
        } description: {
            Text("The scored report appears once the candidate completes the test.")
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    var candidate: String {
        if let name = session.candidateName, !name.isEmpty {
            return name
        }
        if let email = session.candidateEmail, !email.isEmpty {
            return email
        }
        return String(localized: "Unknown candidate")
    }
}
