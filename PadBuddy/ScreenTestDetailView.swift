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
    @State private var detail: ScreenTestSession?
    /// Which (session, client) produced `detail`: numeric session ids collide across
    /// Screen accounts, so an id-only identity let a reused view show or refetch the
    /// wrong account's report (#1860).
    @State private var detailFor: FetchIdentity?
    /// Monotonic id of the newest `refetch()`: without it, a slow response for a
    /// previous selection could land after a newer one and overwrite `detail` (#1861).
    @State private var fetchGeneration = 0
    /// A failed refetch (#921): the list's copy stays on screen, but flagged stale
    /// rather than silently posing as the session's current state.
    @State private var refreshError: String?
    @State private var isFetchingReport = false
    @State private var reportError: String?
    // Optional report-export options (#443), mapped onto the Screen API's PDF query
    // params. All default off, so an untouched export keeps the server's defaults.
    @State private var exportAnonymized = false
    @State private var exportIncludeRank = false
    @State private var exportIncludeComparative = false
    #if !os(macOS)
        /// The staged PDF Quick Look is previewing after Open PDF (#808).
        @State private var reportPreviewURL: URL?
        /// The fetched PDF staged for the save-file exporter (#808).
        @State private var pendingReportExport: ScreenReportExportDocument?
    #endif

    /// Session identity for fetches: the id plus the client's account coordinates,
    /// because per-account session ids collide (#1860).
    private struct FetchIdentity: Hashable {
        let testID: Int
        let apiKey: String
        let baseURL: URL
    }

    private var fetchIdentity: FetchIdentity {
        FetchIdentity(testID: test.id, apiKey: client.apiKey, baseURL: client.baseURL)
    }

    /// The session to display: the refetched copy when it belongs to the current
    /// (session, client) identity, else the list's.
    private var session: ScreenTestSession {
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

    private func clearReportPresentationState() {
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

    private func reportSection(_ report: ScreenReport) -> some View {
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

    private func warnings(_ warnings: [String]) -> some View {
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
            .disabled(isFetchingReport)
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
        if let name = session.candidateName, !name.isEmpty {
            return name
        }
        if let email = session.candidateEmail, !email.isEmpty {
            return email
        }
        return String(localized: "Unknown candidate")
    }
}

nonisolated struct ScreenWarningRow: Identifiable, Equatable {
    let id: Int
    let text: String
}

// MARK: - Fetching and report export

// (Formatting + the export document + previews live in
// ScreenTestDetailView+Formatting.swift, split for file length.)

private extension ScreenTestDetailView {
    func refetch() async {
        let identity = fetchIdentity
        if detailFor != identity {
            // The view was reused for another session or account; drop the previous
            // copy so it can't render for the new identity (#1860).
            detail = nil
            detailFor = nil
            refreshError = nil
        }
        fetchGeneration += 1
        let generation = fetchGeneration
        // Non-fatal: the list already gave us a usable session, so a failed refetch
        // leaves the existing data in place - but flagged stale rather than silently
        // presented as the current state (#921).
        do {
            let fresh = try await client.getTest(id: identity.testID, withCommunityStats: true)
            guard generation == fetchGeneration else { return }

            detail = fresh
            detailFor = identity
            refreshError = nil
        } catch is CancellationError {
            return
        } catch {
            // Switching sessions cancels this task; that's not a refresh failure.
            // The generation guard keeps a superseded fetch's error out too (#1861).
            guard generation == fetchGeneration, !Task.isCancelled else { return }

            refreshError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fetches the report PDF, then either opens it (temp file) or offers a save panel.
    func openReport(save: Bool) async {
        let identity = fetchIdentity
        isFetchingReport = true
        defer { isFetchingReport = false }
        do {
            let testID = identity.testID
            let anonymous = exportAnonymized ? true : nil
            let includeRank = exportIncludeRank ? true : nil
            let includeComparativeScore = exportIncludeComparative ? true : nil
            let data = try await ScreenReportOperationLimiter.shared.perform {
                try await client.testReport(
                    id: testID,
                    anonymous: anonymous,
                    includeRank: includeRank,
                    includeComparativeScore: includeComparativeScore
                )
            }
            // The detail view can be reused for another session/account while this
            // request was in flight; discard stale bytes instead of opening them under
            // the new candidate's identity (#4679).
            guard identity == fetchIdentity else { return }

            // The bytes are handed to external viewers / written where the user
            // picked, so require an actual PDF of sane size: a malicious or broken
            // response must not exhaust memory or smuggle arbitrary content to a
            // viewer under a .pdf name (#1862).
            guard ScreenReportFiles.isWithinSizeLimit(data.count) else {
                reportError = String(localized: "The report is too large to open.")
                return
            }
            guard ScreenReportFiles.isLikelyPDF(data) else {
                reportError = String(localized: "The server did not return a PDF report.")
                return
            }

            if save {
                saveReport(data)
            } else {
                #if os(macOS)
                    // Staged in a unique, owner-only temp subdirectory (#804, #807): test
                    // IDs collide across accounts, and reports hold candidate data, so the
                    // file is single-use and swept again after opening / at next launch.
                    let url = try ScreenReportFiles.stage(data, testID: identity.testID)
                    let accepted = NSWorkspace.shared.open(url)
                    ScreenReportFiles.handleOpenResult(accepted, for: url)
                #else
                    // Quick Look previews the staged single-use file, which is swept
                    // again once the viewer has had time to load it (#808).
                    let url = try ScreenReportFiles.stage(data, testID: identity.testID)
                    reportPreviewURL = url
                    ScreenReportFiles.scheduleRemoval(of: url)
                #endif
            }
        } catch {
            guard identity == fetchIdentity else { return }

            reportError = (error as? CoderPadError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Offers a save panel (sandbox-safe: the user grants write access to the chosen
    /// location) and writes the fetched PDF there.
    func saveReport(_ data: Data) {
        #if os(macOS)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "ScreenReport-\(test.id).pdf"
            // Re-check after the modal: the detail may have switched sessions while the
            // panel was open (#4679).
            guard panel.runModal() == .OK, let url = panel.url,
                  FetchIdentity(testID: test.id, apiKey: client.apiKey, baseURL: client.baseURL)
                  == fetchIdentity else { return }

            do {
                try data.write(to: url)
            } catch {
                reportError = error.localizedDescription
            }
        #else
            // The document exporter is sandbox-safe: it writes wherever the user
            // picks, mirroring the macOS save panel (#808).
            pendingReportExport = ScreenReportExportDocument(data: data)
        #endif
    }
}
